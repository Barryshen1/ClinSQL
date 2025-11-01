WITH cohort_copd AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dcode
    ON di.icd_code = dcode.icd_code
   AND di.icd_version = dcode.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (dcode.long_title LIKE '%COPD%' AND dcode.long_title LIKE '%exacerbation%')
),
med_complexity AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND) / 86400 AS los_days,
    COUNT(DISTINCT LOWER(TRIM(ph.medication))) AS medication_complexity
  FROM cohort_copd AS c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` AS ph
    ON ph.subject_id = c.subject_id
   AND ph.hadm_id = c.hadm_id
   AND ph.starttime >= c.admittime
   AND ph.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
),
tertile AS (
  SELECT
    m.*,
    NTILE(3) OVER (ORDER BY m.medication_complexity) AS tertile
  FROM med_complexity AS m
),
readmission_flags AS (
  SELECT
    t.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
        WHERE a2.subject_id = t.subject_id
          AND a2.admittime > t.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(t.dischtime, INTERVAL 30 DAY)
      )
      THEN 1 ELSE 0
    END AS readm30_flag
  FROM tertile AS t
)
SELECT
  tertile AS tertile_group,
  COUNT(*) AS n,
  MIN(medication_complexity) AS min_complexity,
  MAX(medication_complexity) AS max_complexity,
  AVG(medication_complexity) AS mean_complexity,
  AVG(los_days) AS mean_los_days,
  100 * AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_percent,
  100 * AVG(readm30_flag) AS readmission_30_percent
FROM readmission_flags
GROUP BY tertile
ORDER BY tertile;