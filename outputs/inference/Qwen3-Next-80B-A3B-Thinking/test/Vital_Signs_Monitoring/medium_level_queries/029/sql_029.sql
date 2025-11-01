WITH target_population AS (
    SELECT
        i.stay_id,
        AVG(c.valuenum) AS mean_spo2
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
        ON c.stay_id = i.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
        ON c.itemid = d.itemid
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 73 AND 83
        AND d.label LIKE '%SpO2%'
        AND c.charttime BETWEEN i.intime AND i.intime + INTERVAL 24 HOUR
        AND c.valuenum IS NOT NULL
    GROUP BY i.stay_id
)
SELECT
    (COUNTIF(mean_spo2 <= 92) * 100.0) / COUNT(*) AS percentile
FROM target_population;