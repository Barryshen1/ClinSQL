WITH stroke_patients AS (
    SELECT p.subject_id, p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
),
hemorrhagic_stroke AS (
    SELECT diag.subject_id, diag.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
    INNER JOIN stroke_patients sp ON diag.subject_id = sp.subject_id
    WHERE d.long_title LIKE '%hemorrhagic stroke%'
),
icu_stays AS (
    SELECT i.hadm_id, MAX(los) as los
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN hemorrhagic_stroke hs ON i.hadm_id = hs.hadm_id
    WHERE i.los BETWEEN 1 AND 7
    GROUP BY i.hadm_id
),
ultrasounds AS (
    SELECT p.hadm_id, COUNT(*) as us_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
    WHERE p.icd_version = 10
    AND d.long_title LIKE '%ultrasound%'
    GROUP BY p.hadm_id
),
combined AS (
    SELECT 
        icu.hadm_id, 
        icu.los,
        CASE 
            WHEN icu.los BETWEEN 1 AND 4 THEN '1-4'
            WHEN icu.los BETWEEN 5 AND 7 THEN '5-7'
        END AS los_group,
        COALESCE(u.us_count, 0) AS us_count
    FROM icu_stays icu
    LEFT JOIN ultrasounds u ON icu.hadm_id = u.hadm_id
)
SELECT 
    los_group,
    AVG(us_count) AS mean_ultrasounds,
    MIN(us_count) AS min_ultrasounds,
    MAX(us_count) AS max_ultrasounds
FROM combined
GROUP BY los_group
ORDER BY los_group;