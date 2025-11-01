WITH first_gcs AS (
    SELECT 
        ce.subject_id,
        ce.stay_id,
        ce.valuenum AS gcs_total
    FROM (
        SELECT 
            ce.subject_id,
            ce.stay_id,
            ce.charttime,
            ce.valuenum,
            ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime) AS rn
        FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
        WHERE ce.itemid = 198  -- GCS total
    ) ce
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie 
        ON ce.stay_id = ie.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 77 AND 87
        AND ce.rn = 1  -- first GCS measurement for the stay
        AND ce.valuenum IS NOT NULL  -- exclude NULL values
)
SELECT 
    AVG(gcs_total) AS avg_first_gcs
FROM first_gcs;