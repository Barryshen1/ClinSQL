WITH acs_admissions AS (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (
        'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4',
        'I22.0', 'I22.1', 'I22.2', 'I22.3', 'I22.4', 'I22.8', 'I22.9'
    )
),
patient_79_89 AS (
    SELECT p.subject_id, a.hadm_id, p.gender,
           p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS admission_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    WHERE p.gender = 'M'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89
),
acs_patients AS (
    SELECT pa.hadm_id
    FROM patient_79_89 pa
    JOIN acs_admissions acs
        ON pa.hadm_id = acs.hadm_id
),
troponin_initial AS (
    SELECT le.hadm_id, le.valuenum, le.valueuom,
           ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
        ON le.itemid = di.itemid
    WHERE di.label LIKE '%TROPONIN T%'
      AND le.hadm_id IN (SELECT hadm_id FROM acs_patients)
),
troponin_categorized AS (
    SELECT hadm_id,
           CASE
               WHEN valuenum <= 0.01 THEN 'Normal'
               WHEN valuenum > 0.01 AND valuenum <= 0.04 THEN 'Borderline'
               ELSE 'Elevated'
           END AS troponin_category
    FROM troponin_initial
    WHERE rn = 1
      AND valueuom = 'ng/mL'
      AND valuenum IS NOT NULL
)
SELECT troponin_category,
       COUNT(*) AS count,
       ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM troponin_categorized
GROUP BY troponin_category;