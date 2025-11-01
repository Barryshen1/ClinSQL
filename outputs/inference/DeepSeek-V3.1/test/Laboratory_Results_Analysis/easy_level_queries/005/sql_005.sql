WITH first_sodium AS (
    SELECT 
        ie.stay_id,
        le.valuenum AS first_sodium
    FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ie.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
        ON ie.subject_id = le.subject_id 
        AND ie.hadm_id = le.hadm_id 
        AND le.charttime >= ie.intime
        AND le.charttime <= ie.outtime
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d 
        ON le.itemid = d.itemid
    WHERE 
        p.gender = 'M'
        AND p.anchor_age >= 89  -- Patients who are 89 at time of anchor
        AND d.itemid = 50983  -- Sodium (serum)
        AND le.valuenum IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.stay_id ORDER BY le.charttime) = 1
)
SELECT 
    APPROX_QUANTILES(first_sodium, 100)[OFFSET(25)] AS q25,
    APPROX_QUANTILES(first_sodium, 100)[OFFSET(75)] AS q75,
    APPROX_QUANTILES(first_sodium, 100)[OFFSET(75)] - APPROX_QUANTILES(first_sodium, 100)[OFFSET(25)] AS iqr
FROM first_sodium;