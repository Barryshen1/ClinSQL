WITH surgical_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    COALESCE(a.dischtime, a.deathtime) AS end_time,
    a.discharge_location,
    a.hospital_expire_flag,
    a.deathtime,
    p.gender,
    p.anchor_age,
    (a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1) AS is_mortality
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admittime IS NOT NULL
    AND (a.dischtime IS NOT NULL OR a.deathtime IS NOT NULL)
    -- Ensure there is a surgical procedure associated with this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
        ON d.icd_code = pi.icd_code
       AND d.icd_version = pi.icd_version
      WHERE pi.subject_id = a.subject_id
        AND pi.hadm_id = a.hadm_id
        AND (
              LOWER(d.long_title) LIKE '%surg%'
              OR LOWER(d.long_title) LIKE '%operation%'
              OR LOWER(d.long_title) LIKE '%proced%'
            )
    )
)

SELECT
  CASE
    WHEN is_mortality THEN 'In-hospital Mortality'
    WHEN LOWER(discharge_location) LIKE '%home%' THEN 'Discharged Home'
    ELSE 'Discharged to Facility'
  END AS category,
  AVG(TIMESTAMP_DIFF(end_time, admittime, SECOND) / 86400.0) AS mean_los_days,
  STDDEV_POP(TIMESTAMP_DIFF(end_time, admittime, SECOND) / 86400.0) AS sd_los_days,
  100.0 * SUM(CASE
                  WHEN TIMESTAMP_DIFF(end_time, admittime, SECOND) / 86400.0 <= 7 THEN 1
                  ELSE 0
                END) / COUNT(*) AS pct_los_le_7_days
FROM surgical_inpatients
GROUP BY category
ORDER BY category;