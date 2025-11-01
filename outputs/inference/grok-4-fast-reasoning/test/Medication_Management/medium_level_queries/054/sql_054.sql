WITH diabetes_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND LEFT(icd_code, 3) IN ('E10', 'E11', 'E12', 'E13', 'E14'))
),
hf_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
qualifying_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN diabetes_hadm dh
    ON a.hadm_id = dh.hadm_id
  INNER JOIN hf_hadm hh
    ON a.hadm_id = hh.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
    AND a.hospital_expire_flag = 0
),
total_admissions AS (
  SELECT COUNT(DISTINCT hadm_id) AS n_total
  FROM qualifying_admissions
),
first_48h_users AS (
  SELECT COUNT(DISTINCT e.hadm_id) AS n_first
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN qualifying_admissions qa
    ON e.subject_id = qa.subject_id AND e.hadm_id = qa.hadm_id
  WHERE e.charttime >= qa.admittime
    AND e.charttime < TIMESTAMP_ADD(qa.admittime, INTERVAL 48 HOUR)
    AND (
      LOWER(e.medication) LIKE '%liraglutide%'
      OR LOWER(e.medication) LIKE '%semaglutide%'
      OR LOWER(e.medication) LIKE '%dulaglutide%'
      OR LOWER(e.medication) LIKE '%exenatide%'
      OR LOWER(e.medication) LIKE '%lixisenatide%'
      OR LOWER(e.medication) LIKE '%victoza%'
      OR LOWER(e.medication) LIKE '%saxenda%'
      OR LOWER(e.medication) LIKE '%ozempic%'
      OR LOWER(e.medication) LIKE '%rybelsus%'
      OR LOWER(e.medication) LIKE '%trulicity%'
      OR LOWER(e.medication) LIKE '%bydureon%'
      OR LOWER(e.medication) LIKE '%byetta%'
      OR LOWER(e.medication) LIKE '%tanzeum%'
    )
),
final_24h_users AS (
  SELECT COUNT(DISTINCT e.hadm_id) AS n_final
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN qualifying_admissions qa
    ON e.subject_id = qa.subject_id AND e.hadm_id = qa.hadm_id
  WHERE e.charttime >= TIMESTAMP_SUB(qa.dischtime, INTERVAL 24 HOUR)
    AND e.charttime < qa.dischtime
    AND (
      LOWER(e.medication) LIKE '%liraglutide%'
      OR LOWER(e.medication) LIKE '%semaglutide%'
      OR LOWER(e.medication) LIKE '%dulaglutide%'
      OR LOWER(e.medication) LIKE '%exenatide%'
      OR LOWER(e.medication) LIKE '%lixisenatide%'
      OR LOWER(e.medication) LIKE '%victoza%'
      OR LOWER(e.medication) LIKE '%saxenda%'
      OR LOWER(e.medication) LIKE '%ozempic%'
      OR LOWER(e.medication) LIKE '%rybelsus%'
      OR LOWER(e.medication) LIKE '%trulicity%'
      OR LOWER(e.medication) LIKE '%bydureon%'
      OR LOWER(e.medication) LIKE '%byetta%'
      OR LOWER(e.medication) LIKE '%tanzeum%'
    )
)
SELECT
  (f.n_first * 100.0 / t.n_total) AS first_48h_prevalence_pct,
  (fin.n_final * 100.0 / t.n_total) AS final_24h_prevalence_pct,
  ((fin.n_final - f.n_first) * 100.0 / t.n_total) AS net_change_pct
FROM total_admissions t
CROSS JOIN first_48h_users f
CROSS JOIN final_24h_users fin;