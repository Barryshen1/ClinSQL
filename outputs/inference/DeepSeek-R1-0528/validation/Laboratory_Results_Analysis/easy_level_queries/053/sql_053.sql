WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age = 82
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE
        a.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code IN ('43301','43311','43321','43331','43381','43391','43401','43411','43491','436'))
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I63%')
        )
    )
),
first_glucose AS (
  SELECT
    c.hadm_id,
    l.valuenum AS glucose_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  WHERE
    l.itemid IN (50809, 50931)  -- Serum glucose in mg/dL
    AND l.valuenum IS NOT NULL
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY l.charttime) = 1
)
SELECT
  APPROX_QUANTILES(glucose_value, 100)[OFFSET(75)] AS percentile_75
FROM first_glucose;