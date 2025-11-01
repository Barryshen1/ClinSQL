WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    adm.discharge_location,
    adm.hospital_expire_flag,
    pat.gender,
    pat.anchor_age,
    srv.curr_service
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN (
    -- Get the first service for each admission (at admission time)
    SELECT
      subject_id,
      hadm_id,
      curr_service
    FROM (
      SELECT
        subject_id,
        hadm_id,
        curr_service,
        ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime ASC) AS rn
      FROM
        `physionet-data.mimiciv_3_1_hosp.services`
    )
    WHERE rn = 1
  ) srv
    ON adm.subject_id = srv.subject_id AND adm.hadm_id = srv.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND srv.curr_service = 'MED'
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) > 0
)

, disposition_map AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(discharge_location) LIKE '%rehab%' THEN 'Facility'
      WHEN LOWER(discharge_location) LIKE '%skilled%' THEN 'Facility'
      WHEN LOWER(discharge_location) LIKE '%nursing%' THEN 'Facility'
      WHEN LOWER(discharge_location) LIKE '%snf%' THEN 'Facility'
      WHEN LOWER(discharge_location) LIKE '%long%' THEN 'Facility'
      WHEN LOWER(discharge_location) LIKE '%facility%' THEN 'Facility'
      ELSE 'Other'
    END AS disposition
  FROM cohort
)

SELECT
  disposition,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los), 2) AS mean_los,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(25)] AS los_25th,
  APPROX_QUANTILES(los, 2)[SAFE_OFFSET(1)] AS los_50th, -- median
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(75)] AS los_75th,
  APPROX_QUANTILES(los, 100)[SAFE_OFFSET(90)] AS los_90th,
  ROUND(100 * SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*), 1) AS percent_los_le_10_days
FROM
  disposition_map
WHERE
  disposition IN ('Home', 'Facility', 'Death')
GROUP BY
  disposition
ORDER BY
  disposition;