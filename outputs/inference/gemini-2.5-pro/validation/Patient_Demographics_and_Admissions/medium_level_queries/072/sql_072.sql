WITH filtered_admissions AS (
  SELECT
    adm.hadm_id,
    -- Calculate hospital length of stay in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los,
    -- Create a categorical variable for discharge disposition
    CASE
      WHEN adm.hospital_expire_flag = 1
        THEN 'In-hospital death'
      WHEN adm.discharge_location = 'HOSPICE'
        THEN 'Hospice'
      WHEN adm.discharge_location LIKE 'HOME%'
        THEN 'Home'
      ELSE NULL
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  -- Join to a subquery of medicine admissions to avoid duplicate hadm_id rows
  INNER JOIN (
    SELECT DISTINCT
      hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.services`
    WHERE
      curr_service = 'MED'
  ) AS med_adm
    ON adm.hadm_id = med_adm.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 74 AND 84
    -- Ensure the admission has a valid duration
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
SELECT
  discharge_category,
  COUNT(hadm_id) AS number_of_admissions,
  AVG(los) AS mean_los,
  -- Calculate median using approximate quantiles (50th percentile)
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  -- Calculate the proportion of stays <= 5 days
  AVG(CASE WHEN los <= 5 THEN 1.0 ELSE 0.0 END) AS proportion_los_le_5
FROM
  filtered_admissions
WHERE
  discharge_category IS NOT NULL
GROUP BY
  discharge_category
ORDER BY
  discharge_category;