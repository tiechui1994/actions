package utils

import (
	"context"
	"fmt"
	"strings"
	"time"

	"google.golang.org/api/option"
	"google.golang.org/api/youtube/v3"
)

func FetchVideo(apiKey, channelID, now string) (desc, videoID string, err error) {
	service, err := youtube.NewService(context.Background(), option.WithAPIKey(apiKey))
	if err != nil {
		return desc, videoID, err
	}

	count := 0
try:
	list, err := service.Search.List([]string{"snippet"}).
		ChannelId(channelID).
		MaxResults(8).
		Order("date").Do()
	if err != nil {
		if count < 3 {
			count += 1
			time.Sleep(time.Second)
			goto try
		}
		return desc, videoID, err
	}

	if len(list.Items) > 0 {
		for _, v := range list.Items {
			if strings.HasPrefix(v.Snippet.PublishedAt, now) {
				count = 0
			again:
				videos, err := service.Videos.List([]string{"snippet"}).
					Id(list.Items[0].Id.VideoId).Do()
				if err != nil {
					if count < 3 {
						count += 1
						time.Sleep(time.Second)
						goto again
					}
					return desc, videoID, err
				}

				return videos.Items[0].Snippet.Description, list.Items[0].Id.VideoId, nil
			}
		}
	}

	return desc, videoID, fmt.Errorf("today: %v no youtube video", now)
}
