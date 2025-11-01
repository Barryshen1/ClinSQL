WITH cohort AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.gender, pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddiag
    ON diag.icd_code = ddiag.icd_code
    AND diag.icd_version = ddiag.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 63 AND 73
),
dx_t2dm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (di.icd_version = 9 AND di.icd_code LIKE '250%' 
        AND NOT (REGEXP_CONTAINS(di.icd_code, r'250\.0?1') OR REGEXP_CONTAINS(di.icd_code, r'250\.0?3')))
     OR (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
),
dx_hf AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (di.icd_version = 9 AND di.icd_code LIKE '428%')
     OR (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
),
cohort_with_dx AS (
  SELECT c.subject_id, c.hadm_id
  FROM cohort c
  JOIN dx_t2dm t
    ON c.hadm_id = t.hadm_id
  JOIN dx_hf h
    ON c.hadm_id = h.hadm_id
),
adm_times AS (
  SELECT hadm_id, subject_id, admittime, dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM cohort_with_dx)
),
med_admin AS (
  SELECT e.subject_id, e.hadm_id, ed.product_description, e.charttime,
         CASE
           WHEN LOWER(e.medication) LIKE '%insulin%' OR LOWER(ed.product_description) LIKE '%insulin%'
             THEN 'insulin'
           WHEN LOWER(e.medication) LIKE '%metformin%' OR LOWER(e.medication) LIKE '%glipi%' 
                OR LOWER(e.medication) LIKE '%glybur%' OR LOWER(e.medication) LIKE '%glime%'
                OR LOWER(e.medication) LIKE '%pioglit%' OR LOWER(e.medication) LIKE '%rosiglit%'
                OR LOWER(e.medication) LIKE '%acarbose%' OR LOWER(ed.product_description) LIKE '%metformin%'
                OR LOWER(ed.product_description) LIKE '%glipi%' OR LOWER(ed.product_description) LIKE '%glybur%'
                OR LOWER(ed.product_description) LIKE '%glime%' OR LOWER(ed.product_description) LIKE '%pioglit%'
                OR LOWER(ed.product_description) LIKE '%rosiglit%' OR LOWER(ed.product_description) LIKE '%acarbose%'
             THEN 'oral_agent'
           ELSE NULL
         END AS drug_category
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.subject_id = ed.subject_id
    AND e.emar_id = ed.emar_id
    AND e.emar_seq = ed.emar_seq
  WHERE e.hadm_id IN (SELECT hadm_id FROM cohort_with_dx)
),
first_24h AS (
  SELECT DISTINCT ma.drug_category, ma.hadm_id
  FROM med_admin ma
  JOIN adm_times at
    ON ma.hadm_id = at.hadm_id
  WHERE ma.drug_category IS NOT NULL
    AND ma.charttime >= TIMESTAMP(at.admittime)
    AND ma.charttime < TIMESTAMP_ADD(TIMESTAMP(at.admittime), INTERVAL 24 HOUR)
),
final_24h AS (
  SELECT DISTINCT ma.drug_category, ma.hadm_id
  FROM med_admin ma
  JOIN adm_times at
    ON ma.hadm_id = at.hadm_id
  WHERE ma.drug_category IS NOT NULL
    AND ma.charttime >= TIMESTAMP_SUB(TIMESTAMP(at.dischtime), INTERVAL 24 HOUR)
    AND ma.charttime < TIMESTAMP(at.dischtime)
),
prevalences AS (
  SELECT
    dc.drug_category,
    COUNT(DISTINCT f.hadm_id) AS n_first,
    COUNT(DISTINCT l.hadm_id) AS n_final,
    (SELECT COUNT(DISTINCT hadm_id) FROM cohort_with_dx) AS cohort_size
  FROM (SELECT DISTINCT drug_category FROM med_admin WHERE drug_category IS NOT NULL) dc
  LEFT JOIN first_24h f ON dc.drug_category = f.drug_category
  LEFT JOIN final_24h l ON dc.drug_category = l.drug_category
  GROUP BY dc.drug_category
)
SELECT
  drug_category,
  ROUND(100.0 * n_first / cohort_size, 2) AS prevalence_first_pct,
  ROUND(100.0 * n_final / cohort_size, 2) AS prevalence_final_pct,
  ROUND(100.0 * (n_final - n_first) / cohort_size, 2) AS net_change_pp
FROM prevalences
ORDER BY drug_category;