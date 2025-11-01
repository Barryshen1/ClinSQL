WITH sepsis_male AS (
    SELECT DISTINCT d.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON d.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND (
            (d.icd_version = 9 AND d.icd_code IN ('99591', '99592', '78552'))
            OR (d.icd_version = 10 AND d.icd_code LIKE 'A41%' OR d.icd_code LIKE 'R65.2%')
        )
),
platelet_peaks AS (
    SELECT l.subject_id, MAX(l.valuenum) AS peak_platelet
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN sepsis_male s ON l.subject_id = s.subject_id
    WHERE l.itemid = 51265  -- Platelet Count
        AND l.valuenum IS NOT NULL
        AND l.valuenum > 0  -- exclude non-positive values
    GROUP BY l.subject_id
)
SELECT APPROX_QUANTILES(peak_platelet, 100)[OFFSET(75)] AS percentile_75
FROM platelet_peaks;