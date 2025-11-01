WITH cohort AS (
  SELECT 
    s.subject_id, 
    s.hadm_id, 
    s.stay_id,
    s.intime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = s.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'J96%')
          OR (d.icd_version = 9 AND d.icd_code IN ('51881', '51882', '51883', '51884', '51885'))
        )
    )
),

vital_signs AS (
  SELECT 
    c.stay_id,
    ce.itemid,
    ce.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.itemid IN (220052, 220179, 220045)
),

vii_per_stay AS (
  SELECT
    stay_id,
    AVG(CASE 
          WHEN itemid IN (220052, 220179) AND valuenum < 65 THEN 1
          WHEN itemid = 220045 AND valuenum > 100 THEN 1
          ELSE 0 
        END) AS vii
  FROM vital_signs
  GROUP BY stay_id
  HAVING COUNT(*) > 0
)

SELECT
  STDDEV(vii) AS sd_vii,
  APPROX_QUANTILES(vii, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(vii, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(vii, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(vii, 100)[OFFSET(95)] AS p95
FROM vii_per_stay;