WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
          OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` hf
      WHERE hf.subject_id = a.subject_id
        AND hf.hadm_id = a.hadm_id
        AND (
          (hf.icd_version = 10 AND hf.icd_code LIKE 'I50%')
          OR (hf.icd_version = 9 AND hf.icd_code LIKE '428%')
        )
    )
),
first_12h_received AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id
    AND c.hadm_id = e.hadm_id
  WHERE e.charttime >= c.admittime
    AND e.charttime <= DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
    AND EXISTS (
      SELECT 1
      FROM UNNEST([
        '%liraglutide%',
        '%semaglutide%',
        '%dulaglutide%',
        '%exenatide%',
        '%lixisenatide%',
        '%albiglutide%',
        '%victoza%',
        '%saxenda%',
        '%ozempic%',
        '%rybelsus%',
        '%trulicity%',
        '%byetta%',
        '%bydureon%',
        '%adlyxin%'
      ]) AS pattern
      WHERE LOWER(e.medication) LIKE pattern
    )
),
last_12h_received AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id
    AND c.hadm_id = e.hadm_id
  WHERE e.charttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND e.charttime <= c.dischtime
    AND e.charttime >= c.admittime
    AND EXISTS (
      SELECT 1
      FROM UNNEST([
        '%liraglutide%',
        '%semaglutide%',
        '%dulaglutide%',
        '%exenatide%',
        '%lixisenatide%',
        '%albiglutide%',
        '%victoza%',
        '%saxenda%',
        '%ozempic%',
        '%rybelsus%',
        '%trulicity%',
        '%byetta%',
        '%bydureon%',
        '%adlyxin%'
      ]) AS pattern
      WHERE LOWER(e.medication) LIKE pattern
    )
)
SELECT
  COUNT(DISTINCT c.hadm_id) AS total_admissions,
  COUNT(DISTINCT f.hadm_id) AS first_12h_count,
  COUNT(DISTINCT l.hadm_id) AS last_12h_count,
  ROUND(COUNT(DISTINCT f.hadm_id) * 100.0 / COUNT(DISTINCT c.hadm_id), 2) AS percent_first_12h,
  ROUND(COUNT(DISTINCT l.hadm_id) * 100.0 / COUNT(DISTINCT c.hadm_id), 2) AS percent_last_12h,
  ROUND(
    (COUNT(DISTINCT f.hadm_id) * 100.0 / COUNT(DISTINCT c.hadm_id)) -
    (COUNT(DISTINCT l.hadm_id) * 100.0 / COUNT(DISTINCT c.hadm_id)),
    2
  ) AS net_change_percentage_points
FROM cohort c
LEFT JOIN first_12h_received f ON c.hadm_id = f.hadm_id
LEFT JOIN last_12h_received l ON c.hadm_id = l.hadm_id;