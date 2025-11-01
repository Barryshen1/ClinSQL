WITH sepsis_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%sepsis%'
),
male_sepsis_admissions AS (
  SELECT sa.hadm_id
  FROM sepsis_admissions sa
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON sa.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
first_creatinine AS (
  SELECT
    le.hadm_id,
    MIN(le.valuenum) AS first_creatinine_val
  FROM physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  JOIN male_sepsis_admissions msa
    ON le.hadm_id = msa.hadm_id
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON le.hadm_id = a.hadm_id
  WHERE
    LOWER(dl.label) = 'creatinine'
    AND LOWER(dl.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
    AND le.charttime >= a.admittime
    AND le.charttime <= a.dischtime
  GROUP BY le.hadm_id
)

SELECT MAX(first_creatinine_val) AS max_admission_creatinine
FROM first_creatinine;