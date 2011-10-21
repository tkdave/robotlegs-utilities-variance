package org.robotlegs.utilities.variance.base
{
	import flash.display.*;
	import flash.events.*;
	import flash.utils.*;
	
	import org.robotlegs.core.*;
	
	/**
	 * A VariantMediatorMap implementation of IMediatorMap for backwards
	 * compatibility with existing robotlegs code. IMediatorMap is implicitly
	 * invariant, so every function from IMediatorMap translates to its
	 * invariant counterpart from IVariantMediatorMap.
	 */
	public class RLVariantMediatorMap extends VariantMediatorMap implements IMediatorMap
	{
		public function RLVariantMediatorMap(contextView:DisplayObjectContainer, 
											 injector:IInjector, 
											 reflector:IReflector, 
											 filter:IPackageFilters = null)
		{
			super(contextView, injector, reflector, filter);
		}
		
		protected const addExceptions:Dictionary = new Dictionary(false);
		protected const removeExceptions:Dictionary = new Dictionary(false);
		
		public function mapView(viewClassOrName:*, 
								mediatorClass:Class, 
								injectViewAs:* = null, 
								autoCreate:Boolean = true, 
								autoRemove:Boolean = true):void
		{
			viewClassOrName = reflector.getClass(viewClassOrName);
			
			mapMediator(viewClassOrName, mediatorClass, false);
			
			if(injectViewAs != null)
			{
				if(injectViewAs is Class)
				{
					injectViewAs = [injectViewAs];
				}
				
				if(injectViewAs is Array)
				{
					for each(var type:Class in injectViewAs)
					{
						mapMediator(type, mediatorClass, true);
					}
				}
			}
			
			if(!autoCreate)
			{
				addExceptions[viewClassOrName] = true;
			}
			
			if(!autoRemove)
			{
				removeExceptions[viewClassOrName] = true;
			}
			
			if(autoCreate && contextView && contextView is viewClassOrName)
			{
				registerMediators(contextView);
			}
		}
		
		public function unmapView(viewClassOrName:*):void
		{
			viewClassOrName = reflector.getClass(viewClassOrName);
			
			unmapMediator(viewClassOrName, false);
		}
		
		public function createMediator(viewComponent:Object):IMediator
		{
			const mediators:Vector.<IMediator> = registerMediators(viewComponent);
			return mediators.length ? mediators[0] : null
		}
		
		public function registerMediator(viewComponent:Object, mediator:IMediator):void
		{
			mediatorMap[createMediatorName(viewComponent, reflector.getClass(mediator))] = mediator;
		}
		
		public function removeMediator(mediator:IMediator):IMediator
		{
			const mediatorName:String = createMediatorName(mediator.getViewComponent(), reflector.getClass(mediator));
			if(mediatorName in mediatorMap)
			{
				const mediator:IMediator = mediatorMap[mediatorName];
				delete mediatorMap[mediatorName];
				return mediator;
			}
			
			return null;
		}
		
		public function removeMediatorByView(viewComponent:Object):IMediator
		{
			const mediators:Vector.<IMediator> = getMediators(viewComponent);
			if(mediators.length > 0)
			{
				removeMediator(mediators[0]);
				return mediators[0];
			}
			
			return null;
		}
		
		public function retrieveMediator(viewComponent:Object):IMediator
		{
			const mediators:Vector.<IMediator> = getMediators(viewComponent);
			return mediators.length ? mediators[0] : null;
		}
		
		public function hasMapping(viewClassOrName:*):Boolean
		{
			return hasMediatorMapping(viewClassOrName, false);
		}
		
		public function hasMediator(mediator:IMediator):Boolean
		{
			const mediatorName:String = createMediatorName(mediator.getViewComponent(), reflector.getClass(mediator));
			return mediatorName in mediatorMap;
		}
		
		public function hasMediatorForView(viewComponent:Object):Boolean
		{
			return getMediators(viewComponent).length > 0;
		}
		
		protected const singleton:* = getDefinitionByName('mx.core.Singleton');
		
		override protected function addListeners():void
		{
			super.addListeners();
			
			const manager:* = getPopupManager();
			if(manager)
			{
				// The PopUpManager dispatches the 'addPopUp' event just
				// before it adds the popup to the SystemManager's ChildList.
				manager.addEventListener('addPopUp', onPopupAdded, false, 50);
			}
		}
		
		override protected function removeListeners():void
		{
			super.removeListeners();
			
			const manager:* = getPopupManager();
			if(manager)
			{
				manager.removeEventListener('addPopUp', onPopupAdded);
			}
		}
		
		protected function onPopupAdded(event:* /*Request*/):void
		{
			// 'event' is an mx.events.Request.
			// Its value has a reference to the SystemManager 
			const sm:DisplayObject = event.value.sm;
			
			// The next component added to the SystemManager is the new popup.
			sm.addEventListener(Event.ADDED, function(evt:Event):void {
				sm.removeEventListener(evt.type, arguments.callee);
				
				const view:IEventDispatcher = evt.target as IEventDispatcher;
				
				// Register mediators for the new popup.
				onViewAdded(evt);
				
				// Listen for add/removes of the popup's children.
				view.addEventListener(Event.ADDED_TO_STAGE, onViewAdded, useCapture, 0, true);
				view.addEventListener(Event.REMOVED_FROM_STAGE, onViewRemoved, useCapture, 0, true);
				
				// Listen for when the popup is removed, so we can remove its mediators.
				view.addEventListener(Event.REMOVED, function(e:Event):void {
					if(e.eventPhase != EventPhase.AT_TARGET)
						return;
					
					view.removeEventListener(e.type, arguments.callee);
					onViewRemoved(e);
				});
			});
		}
		
		protected function getPopupManager():*
		{
			if(!singleton)
				return null;
			
			return singleton.getInstance('mx.managers::IPopUpManager');
		}
		
		override protected function onViewAdded(e:Event):void
		{
			const view:Object = e.target;
			
			if(!applyFilters(view))
			{
				return;
			}
			
			const type:Class = reflector.getClass(view);
			
			// This is a hack... RL's MediatorMap implementation creates the 
			// Mediator as soon as a view is added to the display list. It should
			// queue and invalidate instead. I'll concede for the sake of
			// backwards compatibility.
			
			if(view in removedViews)
				delete removedViews[view];
			
			if(type in addExceptions)
				return;
			
			registerMediators(view);
//			super.onViewAdded(e);
		}
		
		override protected function onViewRemoved(e:Event):void
		{
			const view:Object = e.target;
			
			if(!applyFilters(view))
			{
				return;
			}
			
			const type:Class = reflector.getClass(view);
			
			if(view in addedViews)
				delete addedViews[view];
			
			if(type in removeExceptions)
				return;
			
			super.onViewRemoved(e);
		}
	}
}
