WITH mortality_by_age AS (
  SELECT
    p.anchor_age,
    -- Calculate the mortality rate for each age group
    -- AVG on a 0/1 flag is equivalent to SUM(flag)/COUNT(*)
    AVG(CAST(a.hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    -- Filter for the specified cohort
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
  GROUP BY
    p.anchor_age
)
-- Calculate the IQR of the mortality rates across the different ages
SELECT
  -- APPROX_QUANTILES(value, 4) returns an array: [min, 25th_percentile, median, 75th_percentile, max]
  -- We access the array elements by their 0-based offset.
  -- IQR = 75th percentile (offset 3) - 25th percentile (offset 1)
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_of_mortality_rate
FROM (
  SELECT
    APPROX_QUANTILES(mortality_rate, 4) AS quantiles
  FROM
    mortality_by_age
);