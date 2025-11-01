WITH female_icu_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    i.stay_id,
    i.los,
    a.discharge_location,
    a.hospital_expire_flag,
    -- Calculate age at admission (anchor_age + (admission_year - anchor_year))
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
    AND a.discharge_location IN ('HOME', 'HOSPICE')
    OR a.hospital_expire_flag = 1
)

SELECT
  discharge_outcome,
  COUNT(*) AS total_stays,
  ROUND(COUNTIF(los <= 7) / COUNT(*) * 100, 1) AS percent_le_7_days,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS p50_los,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS p75_los,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS p90_los,
  APPROX_QUANTILES(los, 4)[OFFSET(4)] AS p95_los
FROM (
  SELECT
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-Hospital Death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_outcome,
    los
  FROM
    female_icu_admissions
)
GROUP BY
  discharge_outcome
ORDER BY
  discharge_outcome;