    // Get the AI insights links
    const aiInsightsLinks = document.querySelectorAll('.ai-insights-link');

    // Add a click event listener to each link
    aiInsightsLinks.forEach(link => {
      link.addEventListener('click', async (e) => {
        e.preventDefault();
         // Remove the highlight class from all other rows
        const highlightedRows = document.querySelectorAll('.highlight');
        highlightedRows.forEach(row => {
          row.classList.remove('highlight');
        });
        const row = link.parentElement.parentElement;
        row.classList.add('highlight');          
        // Get the loading logo and loading animation elements
        document.getElementById('loading-logo').style.display = 'block';
        document.getElementById('loading-animation').style.display = 'block';
        document.getElementById('ai-loading-logo').style.display = 'block';
        document.getElementById('ai-action-loading-logo').style.display = 'block';
        document.getElementById('ai-loading-lines').style.display = 'block';
        document.getElementById('ai-loading-lines2').style.display = 'block';
        if (document.getElementById('audioPlayer')) {
          document.getElementById('ai-insights-action-itemsplaceholder').style.display = 'none';
          document.getElementById('sentimentScore').style.display = 'none';
          document.getElementById('sentimentDesc').style.display = 'none';
          document.getElementById('aiSummary').style.display = 'none';
          document.getElementById('audioPlayer').style.display = 'none';
          document.getElementById('raw_transcript').remove();
          document.getElementById('audioPlayer').remove();
        }
        // Get the doc ID from the link's href attribute
        const docId = link.href.split('/').pop();

        // Make an AJAX request to the API to get the audio file URL
        const response = await fetch(`/api/getAudioFileUrl/${docId}`);
        const data = await response.json();
        
        // Get the placeholder element
        const audioPlayerPlaceholder = document.getElementById('audio-player-placeholder');

        const existingAudioPlayer = document.querySelector('audio');

        // Create a new audio player element
        const audioPlayer = document.createElement('audio');
        audioPlayer.setAttribute("id", "audioPlayer");
        
        
        const rawTranscript = document.createElement('div');
        rawTranscript.setAttribute("id", "raw_transcript");
        // Loop through the transcript and format it
        formattedTranscript = "";
        data.raw_transcript.forEach((item) => {
          formattedTranscript += `<div class="chat-message ${item.speaker === 'Customer' ? 'customer' : 'agent'}">
              <div class="chat-message-timestamp">
                  ${item.timestamp}
              </div>
              <div class="chat-message-speaker">
                  ${item.speaker}
              </div>
              <div class="chat-message-content">
                  ${item.text}
              </div>
            </div>`;
        });

        rawTranscript.innerHTML = formattedTranscript;

        audioPlayer.controls = true;

        
        // Set the audio player's source to the audio file URL
        audioPlayer.src = data.gcsUri;
        document.getElementById('loading-logo').style.display = 'none';
        document.getElementById('loading-animation').style.display = 'none';
        // If there is an existing audio player, replace it with the new one
        if (existingAudioPlayer) {
            existingAudioPlayer.replaceWith(audioPlayer);
            audioPlayerPlaceholder.appendChild(rawTranscript);
          } else {
            // Otherwise, append the new audio player to the page
            audioPlayerPlaceholder.appendChild(audioPlayer);
            audioPlayerPlaceholder.appendChild(rawTranscript);
        }
        // Play the audio file
        audioPlayer.play();
        // Highlight the entire row of the tbody using css and javascript

        const ai_insights_placeholder = document.getElementById('ai-insights-placeholder');
        // Create a new div summary element
        const aiSummary = document.createElement('div');
        aiSummary.setAttribute("id", "aiSummary");

        const sentimentScore = document.createElement('div');
        sentimentScore.setAttribute("id", "sentimentScore");

        const sentimentDesc = document.createElement('div');
        sentimentDesc.setAttribute("id", "sentimentDesc");


        
        const aiSummarymessage = data.aiSummary;
        const sentiment_score = data.sentiment_score;
        const sentiment_description = data.sentiment_desc;
        document.getElementById('ai-loading-logo').style.display = 'none';
        document.getElementById('ai-action-loading-logo').style.display = 'none';
        const existingAiSummary = document.getElementById('aiSummary');
        const existingSentitmentScore = document.getElementById('sentimentScore');
        const existingSentitmentDesc = document.getElementById('sentimentDesc');

        if (existingAiSummary) {
          existingAiSummary.replaceWith(aiSummary);
          existingSentitmentScore.replaceWith(sentimentScore);
          existingSentitmentDesc.replaceWith(sentimentDesc);
          document.getElementById('aiSummary').style.display = 'block';
        } else {
          // Otherwise, append the new audio player to the page
          ai_insights_placeholder.appendChild(aiSummary);
          ai_insights_placeholder.appendChild(sentimentScore);
          ai_insights_placeholder.appendChild(sentimentDesc);
      }
      document.getElementById('ai-loading-lines').style.display = 'none';
      document.getElementById('ai-loading-lines2').style.display = 'none';
      let index = 0; 
      function typeEffect() {
        if (index < aiSummarymessage.length) {
          aiSummary.textContent += aiSummarymessage.charAt(index);
          index++;
          setTimeout(typeEffect, 20); // Adjust delay between characters
        }
      }
      typeEffect(); // Start the effect

    // Assuming you have Font Awesome loaded on your page

    // Calculate values for filled and empty stars
    const filledStars = Math.floor(sentiment_score);  
    const emptyStars = 10 - filledStars;

    // Build the star HTML string
    let starHTML = '';
    for (let i = 0; i < filledStars; i++) {
      starHTML += '<i class="fas fa-star" style="color: orange;"></i>';
    }
    for (let i = 0; i < emptyStars; i++) {
      starHTML += '<i class="far fa-star"></i>'; 
    }

    // Update the DOM

      sentimentScore.innerHTML = "<h1>Sentiment Score</h1><span>" + starHTML + "</span>";
      sentimentDesc.innerHTML = "<h1>Sentiment Detail</h1><span><span>" + sentiment_description + "</span>";



      // Append list of action items, owner, status to ai-insights-action-itemsplaceholder html
const actionItemsPlaceholder = document.getElementById('ai-insights-action-itemsplaceholder');
if (actionItemsPlaceholder.hasChildNodes()) {
  while (actionItemsPlaceholder.firstChild) {
    actionItemsPlaceholder.removeChild(actionItemsPlaceholder.firstChild);
  }
}

document.getElementById('ai-insights-action-itemsplaceholder').style.display = 'block';
data.action_items.forEach((actionItem) => {
  const actionItemElement = document.createElement('div');
  actionItemElement.classList.add('action-item');

  const actionItemText = document.createElement('p');
  actionItemText.classList.add('action-item-text');

  actionItemText.textContent = actionItem.action_item;

  const actionItemOwner = document.createElement('p');
  actionItemOwner.classList.add('action-item-owner');
  actionItemOwner.textContent = `Owner: ${actionItem.owner}`;

  const actionItemStatus = document.createElement('p');
  actionItemStatus.classList.add('action-item-status');
  actionItemStatus.innerHTML = `Status: <i class="fas fa-${actionItem.status === 'completed' ? 'check-circle' : 'clock'}"></i>`;

  actionItemElement.appendChild(actionItemText);
  actionItemElement.appendChild(actionItemOwner);
  actionItemElement.appendChild(actionItemStatus);

  actionItemsPlaceholder.appendChild(actionItemElement);
});




      });
    });