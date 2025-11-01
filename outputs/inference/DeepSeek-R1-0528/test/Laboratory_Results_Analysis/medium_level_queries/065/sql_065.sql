WITH ami_admissions AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'M'
        AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 49 AND 59
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            WHERE 
                di.subject_id = a.subject_id
                AND di.hadm_id = a.hadm_id
                AND (
                    (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
                    OR (di.icd_version = 9 AND di.icd_code LIKE '410%')
                )
        )
),
first_troponin AS (
    SELECT 
        aa.hadm_id,
        le.valuenum AS troponin_value,
        ROW_NUMBER() OVER (
            PARTITION BY le.hadm_id 
            ORDER BY le.charttime, le.labevent_id
        ) AS rn
    FROM ami_admissions aa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON aa.subject_id = le.subject_id
        AND aa.hadm_id = le.hadm_id
    WHERE 
        le.itemid = 51003  -- Troponin T
        AND le.valuenum IS NOT NULL
)
SELECT 
    DISTINCT
    PERCENTILE_CONT(troponin_value, 0.5) OVER () AS median_initial_troponin,
    PERCENTILE_CONT(troponin_value, 0.25) OVER () AS q1_initial_troponin,
    PERCENTILE_CONT(troponin_value, 0.75) OVER () AS q3_initial_troponin
FROM first_troponin
WHERE 
    rn = 1 
    AND troponin_value > 0.04;