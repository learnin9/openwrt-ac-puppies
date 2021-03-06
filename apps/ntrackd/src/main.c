#define _GNU_SOURCE
#define __DEBUG

#include "ntrackd.h"

/* kernel user node message delivery to authd. */

static ntrack_t ntrack;

static int fn_message_disp(void *p)
{
	int ret = -1;
	nt_msghdr_t *hdr = p;
	switch(hdr->type) {
		case en_MSG_PCAP:
		break;
		case en_MSG_NODE:
		break;
		case en_MSG_AUTH:
		{
			auth_msg_t *auth = nt_msg_data(hdr);
			ret = nt_unotify_auth(auth, &ntrack);
		}
		break;

		case en_MSG_NACS:
			{
				nacs_msg_t *nacs = nt_msg_data(hdr);
				ret = nt_unotify_ac(nacs);
			}
			break;

		default:
		{
			nt_error("unknown message. %d\n", hdr->type);
		}
		break;
	}
	return ret;
}

typedef struct {
	int core_id; /* which core, this thread to run on. */
	int running;
	pthread_t tid;
} nt_thread_t;

static void *nt_work_fn(void *d)
{
	rbf_t *rbfp;
	cpu_set_t set;
	nt_thread_t *nth = (nt_thread_t*)d;

	CPU_ZERO(&set);
	CPU_SET(nth->core_id, &set);
	if(sched_setaffinity(0, sizeof(set), &set) == -1) {
		nt_error("set [%d] affinity.\n", nth->core_id);
		return (void*)-1;
	}
	nt_debug("nt work thread on core: %d\n", nth->core_id);

	if(nt_message_init(&rbfp)){
		nt_error("ring buff init failed.\n");
		return (void*)-1;
	}

	nth->running = 1;
	nt_message_process(rbfp, &nth->running, fn_message_disp);
	return 0;
}

int main(int argc, char *argv[])
{
	int i;

	/* to user authd. */
	nt_unotify_init();

	/* mmap init & user/flow info. */
	if (nt_base_init(&ntrack)) {
		nt_error("ntrack message init failed.\n");
		return 0;
	}

	cpu_set_t set;
	CPU_ZERO(&set);
	if (sched_getaffinity(0, sizeof(set), &set) == -1) {
		nt_error("get cpuset error: %s\n", strerror(errno));
		exit(EXIT_FAILURE);
	}

	nt_info("core total nums[%d]\n", CPU_COUNT(&set));
	nt_thread_t *threads = malloc(sizeof(nt_thread_t) * CPU_COUNT(&set));
	for (i=0; i<CPU_COUNT(&set); i++) {
		pthread_attr_t attr;
		pthread_attr_init(&attr);

		threads[i].core_id = i;
		if(pthread_create(&threads[i].tid, &attr, nt_work_fn, &threads[i]) !=0 ) {
			nt_error("create [%d] work thread.\n", i);
			exit(EXIT_FAILURE);
		}
	}

	for(i=0; i<CPU_COUNT(&set); i++) {
		void *res;
		if(pthread_join(threads[i].tid, &res) !=0 ) {
			nt_error("join thread[%d] error.\n", i);
			exit(EXIT_FAILURE);
		}
		nt_info("join %d: %p\n", i, res);
		free(res);
	}
	free(threads);
	return 0;
}
