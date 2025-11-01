WITH dialysis_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE LOWER(d.long_title) LIKE '%dialysis%'
    
    UNION DISTINCT
    
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di 
        ON pe.itemid = di.itemid
    WHERE LOWER(di.label) LIKE '%dialysis%'
),

female_77_87 AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F'
      AND anchor_age BETWEEN 77 AND 87
),

eligible_patients AS (
    SELECT f.subject_id
    FROM female_77_87 f
    JOIN dialysis_patients d ON f.subject_id = d.subject_id
),

first_icu_stay AS (
    SELECT 
        i.subject_id,
        i.los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN eligible_patients e ON i.subject_id = e.subject_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) = 1
)

SELECT 
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS q1,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) AS q3,
    (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los)) AS iqr
FROM first_icu_stay;