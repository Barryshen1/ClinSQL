WITH diabetes_heart_failure AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.dischtime IS NOT NULL
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime
  HAVING
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) = 1
    AND
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' OR LOWER(dd.long_title) LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) = 1
),

glp1_flags AS (
  SELECT
    d.hadm_id,
    d.subject_id,
    d.admittime,
    d.dischtime,
    MAX(CASE
          WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide)')
               AND pr.starttime BETWEEN d.admittime AND TIMESTAMP_ADD(d.admittime, INTERVAL 72 HOUR)
          THEN 1 ELSE 0
        END) AS first72,
    MAX(CASE
          WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'(liraglutide|exenatide|dulaglutide|semaglutide|lixisenatide|albiglutide)')
               AND pr.starttime BETWEEN TIMESTAMP_SUB(d.dischtime, INTERVAL 72 HOUR) AND d.dischtime
          THEN 1 ELSE 0
        END) AS final72
  FROM diabetes_heart_failure AS d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = d.subject_id
   AND pr.hadm_id = d.hadm_id
  GROUP BY d.hadm_id, d.subject_id, d.admittime, d.dischtime
)

SELECT
  COUNT(*) AS total_admissions,
  SAFE_DIVIDE(SUM(first72), COUNT(*)) * 100 AS first72_rate_percent,
  SAFE_DIVIDE(SUM(final72), COUNT(*)) * 100 AS final72_rate_percent,
  (SAFE_DIVIDE(SUM(final72), COUNT(*)) * 100) - (SAFE_DIVIDE(SUM(first72), COUNT(*)) * 100) AS absolute_change_percent,
  SAFE_DIVIDE(
     (SAFE_DIVIDE(SUM(final72), COUNT(*)) * 100) - (SAFE_DIVIDE(SUM(first72), COUNT(*)) * 100),
     NULLIF(SAFE_DIVIDE(SUM(first72), COUNT(*)) * 100, 0)
  ) * 1 AS relative_change_percent
FROM glp1_flags;