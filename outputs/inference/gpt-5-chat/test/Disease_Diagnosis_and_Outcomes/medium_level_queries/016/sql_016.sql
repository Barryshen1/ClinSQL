WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- age/gender filter
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    -- include AMI diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        )
    )
    -- exclude shock or respiratory failure
    AND NOT EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.hadm_id = a.hadm_id
        AND (
          (dx.icd_version = 9 AND (
              dx.icd_code = '78551' -- cardiogenic shock
              OR dx.icd_code IN ('51881','51882','51884') -- resp failure codes
          ))
          OR (dx.icd_version = 10 AND (
              dx.icd_code = 'R570' -- cardiogenic shock
              OR dx.icd_code LIKE 'J96%' -- resp failure
          ))
        )
    )
),
icu_flag AS (
  SELECT
    c.hadm_id,
    CASE WHEN COUNTIF(
      -- ICU stay starts before 24h mark and ends after admission start
      i.intime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
      AND i.outtime > c.admittime
    ) > 0 THEN 1 ELSE 0 END AS icu_day1_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
  GROUP BY c.hadm_id
),
final AS (
  SELECT
    c.*,
    f.icu_day1_flag,
    CASE WHEN c.los_days <= 5 THEN '<=5' ELSE '>5' END AS los_group
  FROM cohort c
  JOIN icu_flag f
    ON c.hadm_id = f.hadm_id
)
SELECT
  los_group,
  icu_day1_flag,
  COUNT(*) AS n_admissions,
  ROUND(100 * AVG(hospital_expire_flag), 1) AS mortality_pct,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los
FROM final
GROUP BY los_group, icu_day1_flag
ORDER BY los_group, icu_day1_flag;