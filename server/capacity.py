"""Bounded capacity for this small server; tune through service environment."""
import os
from dataclasses import dataclass, fields


@dataclass(frozen=True)
class CapacityLimits:
    connections: int = 160
    requests: int = 128
    polls: int = 96
    uploads: int = 1
    downloads: int = 2
    backlog: int = 128
    retry_after: int = 3

    def __post_init__(self):
        if any(type(getattr(self, f.name)) is not int or not (0 if f.name == 'polls' else 1)
               <= getattr(self, f.name) <= 4096 for f in fields(self)):
            raise ValueError('Capacity limits must be integers between 1 and 4096')
        if self.requests > self.connections or max(self.uploads, self.downloads) > self.requests:
            raise ValueError('Request and media limits must fit inside connection capacity')
        if self.polls >= self.requests:
            raise ValueError('Poll capacity must leave room for short requests')
        if self.retry_after > 30:
            raise ValueError('Retry delay must be at most 30 seconds')

    @classmethod
    def from_environment(cls):
        defaults = cls()
        return cls(**{f.name: int(os.environ.get('MEIKE_MAX_'+f.name.upper(), getattr(defaults, f.name)))
                      for f in fields(cls)})
