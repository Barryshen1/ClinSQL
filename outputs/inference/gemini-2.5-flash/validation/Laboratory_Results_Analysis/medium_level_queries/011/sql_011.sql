WITH PatientAdmissions AS (
    SELECT
        pa.subject_id,
        ad.hadm_id,
        ad.admittime
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` ad
        ON pa.subject_id = ad.subject_id
    WHERE
        pa.gender = 'M'
        AND pa.anchor_age BETWEEN 61 AND 71
),
ChestPainAdmissions AS (
    SELECT DISTINCT
        pa.subject_id,
        pa.hadm_id,
        pa.admittime
    FROM
        PatientAdmissions pa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        ON pa.subject_id = di.subject_id AND pa.hadm_id = di.hadm_id
    WHERE
        -- Using ICD-10 codes for chest pain
        di.icd_version = 10
        AND di.icd_code IN ('R07.0', 'R07.1', 'R07.2', 'R07.4')
),
FirstTnT AS (
    SELECT
        cpa.subject_id,
        cpa.hadm_id,
        le.valuenum,
        ROW_NUMBER() OVER (PARTITION BY cpa.hadm_id ORDER BY le.charttime) AS rn
    FROM
        ChestPainAdmissions cpa
    JOIN
        `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON cpa.subject_id = le.subject_id
        AND cpa.hadm_id = le.hadm_id
    WHERE
        le.itemid = 51003 -- Itemid for Troponin T, High Sensitivity from d_labitems
        AND le.valuenum IS NOT NULL
        -- Restrict to lab tests performed within the first 24 hours of admission for 'initial'
        AND le.charttime BETWEEN cpa.admittime AND DATETIME_ADD(cpa.admittime, INTERVAL 24 HOUR)
),
CategorizedTnT AS (
    SELECT
        hadm_id,
        CASE
            WHEN valuenum < 6 THEN 'Normal' -- Hs-TnT < 6 ng/L
            WHEN valuenum >= 6 AND valuenum <= 12 THEN 'Borderline' -- Hs-TnT 6-12 ng/L
            WHEN valuenum > 12 THEN 'Myocardial Injury' -- Hs-TnT > 12 ng/L
            ELSE 'Other/Unknown' -- Fallback for unexpected values
        END AS tnt_category
    FROM
        FirstTnT
    WHERE
        rn = 1 -- Select only the first hs-TnT result for each admission
)
SELECT
    tnt_category,
    COUNT(hadm_id) AS count_admissions,
    ROUND(COUNT(hadm_id) * 100.0 / SUM(COUNT(hadm_id)) OVER (), 2) AS percentage_distribution
FROM
    CategorizedTnT
GROUP BY
    tnt_category
ORDER BY
    CASE tnt_category
        WHEN 'Normal' THEN 1
        WHEN 'Borderline' THEN 2
        WHEN 'Myocardial Injury' THEN 3
        ELSE 4
    END;