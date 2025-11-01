WITH first_admissions AS (
    SELECT 
        a.subject_id,
        a.hadm_id,
        a.admittime,
        p.gender,
        -- Compute birth date from anchor_year and anchor_age
        DATE_SUB(CAST(CONCAT(p.anchor_year, '-01-01') AS DATE), INTERVAL p.anchor_age YEAR) AS birth_date,
        TIMESTAMP_DIFF(a.admittime, birth_date, YEAR) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
        p.gender = 'F'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1  -- first admission per patient
),
ischemic_admissions AS (
    SELECT 
        fa.subject_id,
        fa.hadm_id,
        fa.admittime,
        fa.age_at_admission
    FROM first_admissions fa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
        ON fa.subject_id = di.subject_id AND fa.hadm_id = di.hadm_id
    WHERE 
        di.seq_num = 1  -- primary diagnosis
        AND (
            (di.icd_version = 9 AND di.icd_code LIKE '410%' OR di.icd_code LIKE '411%' OR di.icd_code LIKE '412%' OR di.icd_code LIKE '413%' OR di.icd_code LIKE '414%')
            OR 
            (di.icd_version = 10 AND di.icd_code LIKE 'I20%' OR di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I23%' OR di.icd_code LIKE 'I24%' OR di.icd_code LIKE 'I25%')
        )
        AND fa.age_at_admission BETWEEN 36 AND 46
),
troponin_measurements AS (
    SELECT 
        lm.subject_id,
        lm.hadm_id,
        lm.charttime,
        lm.valuenum,
        lm.valueuom
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` lm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
        ON lm.itemid = dli.itemid
    WHERE 
        (LOWER(dli.label) LIKE '%high-sensitivity troponin t%' 
         OR LOWER(dli.label) LIKE '%hs-tn t%' 
         OR LOWER(dli.label) LIKE '%high sensitivity troponin t%')
        AND lm.valueuom = 'ng/L'  -- ensure unit is ng/L
),
first_troponin_per_admission AS (
    SELECT 
        tm.subject_id,
        tm.hadm_id,
        tm.valuenum AS initial_troponin,
        ROW_NUMBER() OVER (PARTITION BY tm.subject_id, tm.hadm_id ORDER BY tm.charttime) AS rn
    FROM troponin_measurements tm
    INNER JOIN ischemic_admissions ia 
        ON tm.subject_id = ia.subject_id AND tm.hadm_id = ia.hadm_id
    WHERE 
        tm.charttime BETWEEN ia.admittime AND TIMESTAMP_ADD(ia.admittime, INTERVAL 24 HOUR)
        AND tm.valuenum > 14  -- > ULN (14 ng/L)
)
SELECT 
    APPROX_QUANTILES(initial_troponin, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(initial_troponin, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(initial_troponin, 100)[OFFSET(75)] AS p75,
    MIN(initial_troponin) AS min,
    MAX(initial_troponin) AS max
FROM first_troponin_per_admission
WHERE rn = 1;