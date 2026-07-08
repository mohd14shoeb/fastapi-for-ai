from fastapi import APIRouter, HTTPException
from bs4 import BeautifulSoup
from config import settings
import requests

router = APIRouter(prefix="/webcrawl", tags=["Web Crawling"])


@router.get("/news")
def crawl_webpage(page: int = 1, limit: int = 5):
    try:
        response = requests.get(settings.CRAWLING_URL)
        response.raise_for_status()  # Raise an error for bad responses
    except requests.RequestException as e:
        raise HTTPException(status_code=400, detail=f"Error fetching the URL: {e}")

    soup = BeautifulSoup(response.content, "html.parser")
    webDataArray = [{}]

    for a in soup.find_all("span", class_="titleline"):
        title = a.text.strip()
        if title:
            dictionaryValue = {"title": title}
            webDataArray.append(dictionaryValue)
        else:
            continue  # Skip if title is empty
    # Skip if title is empty

    # Pagination logic (if applicable)
    start_page_index = (page - 1) * limit
    end_page_index = start_page_index + limit
    # limit links per page
    return {
        "page": page,
        "limit": limit,
        "total_titles": len(webDataArray)
        - 1,  # Subtract 1 to exclude the initial empty dictionary
        "data": webDataArray[start_page_index:end_page_index],
    }
