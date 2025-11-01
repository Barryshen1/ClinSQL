WITH index_admissions AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
    INNER JOIN (
        SELECT subject_id, MIN(admittime) AS first_admittime
        FROM `physionet-data.mimiciv_3_1_hosp`.admissions
        GROUP BY subject_id
    ) b ON a.subject_id = b.subject_id AND a.admittime = b.first_admittime
),
patients_95_male AS (
    SELECT p.subject_id
    FROM `physionet-data.mimiciv_3_1_hosp`.patients p
    WHERE p.gender = 'M'
      AND p.anchor_age = 95
),
pneumonia_admissions AS (
    SELECT d.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dd 
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE dd.icd_version = 10
      AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
eligible_admissions AS (
    SELECT i.hadm_id, i.admittime, i.dischtime
    FROM index_admissions i
    INNER JOIN patients_95_male p ON i.subject_id = p.subject_id
    INNER JOIN pneumonia_admissions d ON i.hadm_id = d.hadm_id
),
creatinine_values AS (
    SELECT l.hadm_id, l.valuenum
    FROM `physionet-data.mimiciv_3_1_hosp`.labevents l
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl 
      ON l.itemid = dl.itemid
    INNER JOIN eligible_admissions e ON l.hadm_id = e.hadm_id
    WHERE dl.itemid = 50809   -- serum creatinine
      AND l.valuenum IS NOT NULL
      AND l.valuenum > 0
      AND l.charttime BETWEEN e.admittime AND e.dischtime
),
peak_creatinine_per_admission AS (
    SELECT c.hadm_id, MAX(c.valuenum) AS peak_creatinine
    FROM creatinine_values c
    GROUP BY c.hadm_id
)
SELECT STDDEV(peak_creatinine) AS std_dev_peak_creatinine
FROM peak_creatinine_per_admission;