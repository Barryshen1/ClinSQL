WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- Sepsis diagnosis
    JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        (
          (d.icd_version = 10 AND (LEFT(d.icd_code, 3) IN ('A40', 'A41')))
          OR
          (d.icd_version = 9 AND (
            d.icd_code IN ('99591', '99592', '78552', '9993', '7907')
            OR LEFT(d.icd_code, 3) = '038'
          ))
        )
    ) sepsis
      ON a.hadm_id = sepsis.hadm_id
    -- Exclude septic shock
    LEFT JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE
        (
          (d.icd_version = 10 AND (d.icd_code IN ('R6521', 'R572')))
          OR
          (d.icd_version = 9 AND d.icd_code = '78552')
        )
    ) shock
      ON a.hadm_id = shock.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    AND shock.hadm_id IS NULL
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
diagnostic_procs AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.icd_code,
    pr.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
      ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
  WHERE
    LOWER(dp.long_title) LIKE '%diagnostic%'
)
SELECT
  CASE
    WHEN sub.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN sub.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  AVG(sub.proc_count) AS mean_diagnostic_procs
FROM (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los_days,
    COUNT(DISTINCT dp.icd_code) AS proc_count
  FROM
    cohort c
    LEFT JOIN diagnostic_procs dp
      ON c.subject_id = dp.subject_id AND c.hadm_id = dp.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.los_days
) sub
WHERE
  sub.los_days BETWEEN 1 AND 7
GROUP BY los_group
ORDER BY los_group;