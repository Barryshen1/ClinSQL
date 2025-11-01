WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 87 AND 97
),
dispo AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    a.hospital_expire_flag,
    a.discharge_location,
    -- Assign disposition
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%snf%'
        OR LOWER(a.discharge_location) LIKE '%rehab%'
        OR LOWER(a.discharge_location) LIKE '%nursing%'
        OR LOWER(a.discharge_location) LIKE '%facility%'
        OR LOWER(a.discharge_location) LIKE '%hospice%'
        OR LOWER(a.discharge_location) LIKE '%long term%'
        OR LOWER(a.discharge_location) LIKE '%skilled%'
        OR LOWER(a.discharge_location) LIKE '%assisted%'
        OR LOWER(a.discharge_location) LIKE '%inpatient%' THEN 'Facility'
      ELSE 'Other'
    END AS disposition
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON c.hadm_id = a.hadm_id
  WHERE
    c.los IS NOT NULL
    AND a.discharge_location IS NOT NULL
)
SELECT
  disposition,
  COUNT(*) AS n,
  ROUND(AVG(los),2) AS mean_los,
  ROUND(STDDEV(los),2) AS sd_los,
  ROUND(100.0 * SUM(CASE WHEN los < 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_los_lt_10
FROM
  dispo
WHERE
  disposition IN ('Home', 'Facility', 'In-hospital death')
GROUP BY
  disposition
ORDER BY
  disposition;