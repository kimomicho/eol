if(!EOL) var EOL = {};
if(!EOL.Curation) EOL.Curation = {};

EOL.Curation.quick_curate = function(e) {
  $$('#right-image-buttons #spinner img')[0].appear();
  new Ajax.Request(this.href, {asynchronous:true, evalScripts:true, onComplete:EOL.Curation.after_quick_curate});
  e.stop();  
};

EOL.Curation.after_quick_curate = function() {
  $$('#right-image-buttons #spinner img')[0].disappear();
  $('large-image-trust-button').disappear();
  $('large-image-untrust-button').disappear();
};

EOL.Curation.Behaviors = {
  '#large-image-curator-button-popup-link_popup_content .visibility input:click': function(e) {
    $$('#large-image-curator-button-popup-link_popup_content .visibility form')[0].onsubmit();
    $$('#large-image-curator-button-popup-link_popup_content .visibility form img')[0].appear();
    $$('#large-image-curator-button-popup-link_popup_content .visibility form')[0].disable();
  },
  
  '#large-image-curator-button-popup-link_popup_content .vetted input:click': function(e) {
    $$('#large-image-curator-button-popup-link_popup_content .vetted form')[0].onsubmit();
    $$('#large-image-curator-button-popup-link_popup_content .vetted form img')[0].appear();
    $$('#large-image-curator-button-popup-link_popup_content .vetted form')[0].disable();
  },
  
  '#large-image-trust-button a:click': function(e) {
    EOL.Curation.quick_curate(e);
  },
  
  '#large-image-untrust-button a:click': function(e) {
    EOL.Curation.quick_curate(e);
  }
};