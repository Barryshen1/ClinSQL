WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender, 
        p.anchor_age,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    WHERE 
        p.gender = 'F'
        AND p.anchor_age BETWEEN 53 AND 63
        AND d.icd_code LIKE 'K92%'  -- Upper GI bleeding codes
        AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),

procedures_per_admission AS (
    SELECT 
        c.hadm_id,
        c.los_days,
        COUNT(DISTINCT p.icd_code) AS num_procedures
    FROM cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
        ON c.hadm_id = p.hadm_id AND c.subject_id = p.subject_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
        ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
    WHERE 
        -- Filter for diagnostic GI procedures
        (dp.long_title LIKE '%endoscopy%' OR dp.long_title LIKE '%esophagoscopy%' 
         OR dp.long_title LIKE '%gastroscopy%' OR dp.long_title LIKE '%duodenoscopy%')
    GROUP BY c.hadm_id, c.los_days
)

SELECT 
    CASE 
        WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
        WHEN los_days BETWEEN 5 AND 8 THEN '5-8 days'
    END AS stay_group,
    COUNT(hadm_id) AS num_admissions,
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75
FROM procedures_per_admission
GROUP BY stay_group
ORDER BY stay_group;