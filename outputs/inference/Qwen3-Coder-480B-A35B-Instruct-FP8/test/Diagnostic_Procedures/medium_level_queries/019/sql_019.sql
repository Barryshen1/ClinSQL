WITH target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 42 AND 52
),

pancreatitis_admissions AS (
  SELECT DISTINCT a.subject_id, a.hadm_id,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN target_patients tp ON a.subject_id = tp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%acute pancreatitis%'
),

los_groups AS (
  SELECT *,
         CASE
           WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
           WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
         END AS los_group
  FROM pancreatitis_admissions
  WHERE los_days BETWEEN 1 AND 7
),

procedure_counts AS (
  SELECT lg.hadm_id, lg.los_group, COUNT(*) AS proc_count
  FROM los_groups lg
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr ON lg.hadm_id = pr.hadm_id
  GROUP BY lg.hadm_id, lg.los_group
)

SELECT
  los_group,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(proc_count) AS mean_procedures,
  MIN(proc_count) AS min_procedures,
  MAX(proc_count) AS max_procedures
FROM procedure_counts
GROUP BY los_group
ORDER BY los_group;