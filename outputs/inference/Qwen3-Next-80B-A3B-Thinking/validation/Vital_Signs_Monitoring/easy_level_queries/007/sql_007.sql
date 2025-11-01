WITH respiratory_events AS (
    SELECT
        a.hadm_id,
        c.charttime,
        c.valuenum,
        ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY c.charttime) AS rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` c ON a.hadm_id = c.hadm_id
    JOIN
        `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 73 AND 83
        AND d.label = 'Respiratory Rate'
        AND c.charttime BETWEEN a.admittime AND a.dischtime
        AND c.valuenum IS NOT NULL
)
SELECT
    STDDEV(valuenum) AS std_dev_respiratory_rate
FROM
    respiratory_events
WHERE
    rn = 1;