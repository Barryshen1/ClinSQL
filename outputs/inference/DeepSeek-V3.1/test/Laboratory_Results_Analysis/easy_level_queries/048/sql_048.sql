WITH coppat AS (
    -- Female patients with COPD admissions
    SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
        ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        ON adm.hadm_id = dx.hadm_id
    WHERE pat.gender = 'F'
        AND (
            (dx.icd_version = 9 AND dx.icd_code LIKE '491%' OR dx.icd_code LIKE '492%' OR dx.icd_code = '496')
            OR (dx.icd_version = 10 AND dx.icd_code LIKE 'J41%' OR dx.icd_code LIKE 'J42%' OR dx.icd_code LIKE 'J43%' OR dx.icd_code LIKE 'J44%')
        )
),
creat_first24h AS (
    -- Average creatinine per admission in first 24h
    SELECT cp.hadm_id, AVG(le.valuenum) AS avg_creat
    FROM coppat cp
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
        ON cp.hadm_id = le.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
        ON le.itemid = dli.itemid
    WHERE dli.itemid = 50912  -- Serum creatinine
        AND le.charttime BETWEEN cp.admittime AND DATETIME_ADD(cp.admittime, INTERVAL 24 HOUR)
        AND le.valuenum IS NOT NULL  -- Ensure numeric value
    GROUP BY cp.hadm_id
)
-- Compute 75th percentile of average creatinine values
SELECT APPROX_QUANTILES(avg_creat, 100)[OFFSET(75)] AS percentile_75
FROM creat_first24h;