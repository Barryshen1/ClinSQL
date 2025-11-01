WITH mean_dbp_per_stay AS (
    SELECT 
        ie.stay_id,
        AVG(ce.valuenum) AS mean_dbp
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
        ON ie.stay_id = ce.stay_id
    WHERE 
        p.gender = 'M'
        AND p.anchor_age BETWEEN 49 AND 59
        AND ie.first_careunit IN ('Step Down', 'Intermediate Care')
        AND ce.itemid IN (220180, 225310)  -- Diastolic BP itemids
        AND ce.valuenum IS NOT NULL
        AND ce.charttime >= ie.intime
        AND ce.charttime <= ie.outtime
    GROUP BY ie.stay_id
    HAVING COUNT(ce.valuenum) > 0  -- Ensure at least one measurement
)
SELECT 
    APPROX_QUANTILES(mean_dbp, 100)[OFFSET(25)] AS q1,
    APPROX_QUANTILES(mean_dbp, 100)[OFFSET(75)] AS q3,
    APPROX_QUANTILES(mean_dbp, 100)[OFFSET(75)] - APPROX_QUANTILES(mean_dbp, 100)[OFFSET(25)] AS iqr
FROM mean_dbp_per_stay;