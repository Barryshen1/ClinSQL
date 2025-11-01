WITH sepsis_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    -- Sepsis ICD codes (example: A41.x, R65.20, etc.)
    (
      (d.icd_version = 10 AND d.icd_code IN ('A419', 'R6520')) OR
      (d.icd_version = 9 AND d.icd_code = '0389')
    )
    -- Exclude septic shock
    AND a.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
      ON d2.icd_code = dd2.icd_code AND d2.icd_version = dd2.icd_version
      WHERE
        (d2.icd_version = 10 AND d2.icd_code IN ('R6521', 'T8112XA', 'T8112XD')) OR
        (d2.icd_version = 9 AND d2.icd_code IN ('78552', '99592'))
    )
),
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 87 AND 97
),
admissions_filtered AS (
  SELECT
    sa.hadm_id,
    sa.los_days,
    CASE
      WHEN sa.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN sa.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM sepsis_admissions sa
  JOIN eligible_patients ep ON sa.subject_id = ep.subject_id
  WHERE sa.los_days BETWEEN 1 AND 7
),
procedure_counts AS (
  SELECT
    af.hadm_id,
    af.los_group,
    COUNT(p.hadm_id) AS proc_count
  FROM admissions_filtered af
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    ON af.hadm_id = p.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp
    ON p.icd_code = dp.icd_code AND p.icd_version = dp.icd_version
  WHERE
    -- Filter for diagnostic procedures
    LOWER(dp.long_title) LIKE '%diagnostic%'
  GROUP BY af.hadm_id, af.los_group
)
SELECT
  los_group,
  AVG(proc_count) AS mean_procedures
FROM procedure_counts
GROUP BY los_group
ORDER BY los_group;