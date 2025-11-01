WITH cohort AS (
  SELECT
    i.hadm_id,
    i.stay_id,
    i.los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital Death'
      WHEN a.discharge_location LIKE '%HOME%' THEN 'Home'
      WHEN a.discharge_location LIKE '%SNF%' OR
           a.discharge_location LIKE '%REHAB%' OR
           a.discharge_location LIKE '%NURSING%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM
    physionet-data.mimiciv_3_1_icu.icustays i
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON i.hadm_id = a.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
)

SELECT
  discharge_group,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  STDDEV_SAMP(los) AS stddev_los,
  AVG(CASE WHEN los < 10 THEN 1 ELSE 0 END) * 100 AS percent_los_lt_10_days
FROM
  cohort
WHERE
  discharge_group IN ('Home', 'Facility', 'In-hospital Death')
GROUP BY
  discharge_group
ORDER BY
  discharge_group;