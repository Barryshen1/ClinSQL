WITH admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE
        (d.icd_version = 9 AND d.icd_code LIKE '410%')
        OR
        (d.icd_version = 10 AND d.icd_code BETWEEN 'I21' AND 'I249')
    )
),
los_groups AS (
  SELECT
    hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM admissions_filtered
  WHERE los_days BETWEEN 1 AND 7
),
ultrasound_procs AS (
  SELECT
    pe.hadm_id,
    COUNT(*) AS ultrasound_count
  FROM
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    pe.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%ultrasound%' OR LOWER(di.label) LIKE '%echocardiography%'
    AND pe.value IS NOT NULL
  GROUP BY
    pe.hadm_id
)
SELECT
  lg.los_group,
  COUNT(DISTINCT lg.hadm_id) AS patient_count,
  AVG(COALESCE(up.ultrasound_count, 0)) AS mean_ultrasounds_per_admission
FROM
  los_groups lg
LEFT JOIN
  ultrasound_procs up
ON
  lg.hadm_id = up.hadm_id
GROUP BY
  lg.los_group
ORDER BY
  lg.los_group;