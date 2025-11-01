WITH cohort_outcomes AS (
  SELECT
    adm.hadm_id,
    -- Calculate hospital length of stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS hospital_los,
    -- Categorize the discharge outcome
    CASE
      WHEN adm.hospital_expire_flag = 1
        THEN 'In-hospital Death'
      WHEN adm.discharge_location IN ('HOME', 'HOME HEALTH CARE')
        THEN 'Discharged Home'
      WHEN adm.discharge_location IN (
        'SKILLED NURSING FACILITY',
        'REHAB/DISTINCT PART HOSP',
        'CHRONIC/LONG TERM CARE',
        'HOSPICE',
        'OTHER FACILITY',
        'PSYCH FACILITY'
      )
        THEN 'Discharged to Facility'
      ELSE 'Other'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND adm.admission_location = 'TRANSFER FROM OTHER HOSPITAL'
    -- Ensure LOS can be calculated
    AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
)
SELECT
  discharge_category,
  COUNT(hadm_id) AS number_of_patients,
  AVG(hospital_los) AS mean_los,
  STDDEV(hospital_los) AS stddev_los,
  -- Calculate the percentile rank of a 5-day LOS as the proportion of patients with LOS < 5 days
  COUNTIF(hospital_los < 5) / COUNT(hadm_id) AS percentile_rank_of_5_day_los
FROM
  cohort_outcomes
WHERE
  -- Filter for the specified discharge categories and valid LOS
  discharge_category IN ('In-hospital Death', 'Discharged Home', 'Discharged to Facility')
  AND hospital_los >= 0
GROUP BY
  discharge_category
ORDER BY
  discharge_category;