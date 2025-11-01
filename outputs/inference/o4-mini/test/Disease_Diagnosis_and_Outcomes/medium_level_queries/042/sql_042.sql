WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    USING(subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
   AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 69 AND 79
    AND LOWER(dicd.long_title) LIKE '%myocardial infarction%'
    AND NOT EXISTS (
      -- exclude admissions with shock or respiratory failure
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd2
        ON d2.icd_code = dicd2.icd_code
       AND d2.icd_version = dicd2.icd_version
      WHERE d2.subject_id = a.subject_id
        AND d2.hadm_id   = a.hadm_id
        AND (
          LOWER(dicd2.long_title) LIKE '%shock%'
          OR LOWER(dicd2.long_title) LIKE '%respiratory failure%'
        )
    )
),

binned AS (
  SELECT
    *,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE '8+ days'
    END AS los_cat
  FROM cohort
),

summary AS (
  SELECT
    los_cat,
    COUNT(*) AS total_n,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 1) AS mortality_pct,
    -- median LOS via 2-quantile approx, pick the 50th percentile
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los
  FROM binned
  GROUP BY los_cat
),

dist AS (
  SELECT
    los_cat,
    discharge_location,
    COUNT(*) AS loc_n
  FROM binned
  GROUP BY los_cat, discharge_location
),

dist_pct AS (
  SELECT
    d.los_cat,
    d.discharge_location,
    ROUND(100.0 * d.loc_n / s.total_n, 1) AS pct
  FROM dist d
  JOIN summary s
    USING(los_cat)
),

final AS (
  SELECT
    s.los_cat,
    s.mortality_pct,
    s.median_los,
    ARRAY_AGG(STRUCT(
      dp.discharge_location,
      dp.pct
    ) ORDER BY dp.discharge_location) AS discharge_destinations
  FROM summary s
  LEFT JOIN dist_pct dp
    USING(los_cat)
  GROUP BY s.los_cat, s.mortality_pct, s.median_los
)

SELECT *
FROM final
ORDER BY
  CASE los_cat
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    ELSE 3
  END;