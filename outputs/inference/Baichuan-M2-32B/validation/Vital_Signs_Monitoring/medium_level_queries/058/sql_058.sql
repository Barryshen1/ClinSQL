WITH icu_stays AS (
    SELECT 
        i.stay_id,
        i.subject_id,
        i.hadm_id,
        i.intime,
        p.gender,
        (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
        AND (p.anchor_age + EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 38 AND 48
),
sbp_readings AS (
    SELECT 
        s.stay_id,
        s.subject_id,
        s.hadm_id,
        s.intime,
        ce.valuenum AS sbp_value
    FROM icu_stays s
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON s.subject_id = ce.subject_id
        AND s.hadm_id = ce.hadm_id
        AND s.stay_id = ce.stay_id
    WHERE 
        ce.itemid = 442
        AND ce.charttime BETWEEN s.intime AND s.intime + INTERVAL 24 HOUR
),
avg_sbp_per_stay AS (
    SELECT 
        stay_id,
        AVG(sbp_value) AS avg_sbp
    FROM sbp_readings
    GROUP BY stay_id
)
SELECT 
    (COUNTIF(avg_sbp <= 120) * 100.0) / COUNT(*) AS percentile
FROM avg_sbp_per_stay;