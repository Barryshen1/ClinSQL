WITH hepatic_patients AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
    ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(d_icd.long_title) LIKE '%hepatic failure%'
    AND LOWER(d_icd.long_title) LIKE '%liver failure%'
    -- We use OR for multiple patterns since exact wording varies
    OR LOWER(d_icd.long_title) LIKE '%acute liver failure%'
    OR LOWER(d_icd.long_title) LIKE '%chronic liver failure%'
    OR LOWER(d_icd.long_title) LIKE '%liver failure%'
    OR LOWER(d_icd.long_title) LIKE '%hepatic insufficiency%'
    OR LOWER(d_icd.long_title) LIKE '%liver insufficiency%'
    OR d_icd.icd_code IN ('K72.0', 'K72.1', 'K72.9', 'K70.3', 'K71.5')
),

medication_complexity AS (
  SELECT
    hp.subject_id,
    hp.hadm_id,
    hp.admittime,
    hp.dischtime,
    hp.hospital_expire_flag,
    hp.anchor_age,
    COUNT(DISTINCT p.drug) AS med_complexity_score_7day
  FROM hepatic_patients hp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON hp.hadm_id = p.hadm_id
    AND p.starttime >= hp.admittime
    AND p.starttime < TIMESTAMP_ADD(hp.admittime, INTERVAL 7 DAY)
  GROUP BY hp.subject_id, hp.hadm_id, hp.admittime, hp.dischtime, hp.hospital_expire_flag, hp.anchor_age
),

readmission_flag AS (
  SELECT
    hp.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = hp.subject_id
          AND a2.admittime > hp.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(hp.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS thirty_day_readmission
  FROM hepatic_patients hp
),

final_cohort AS (
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.admittime,
    mc.dischtime,
    mc.med_complexity_score_7day,
    TIMESTAMP_DIFF(mc.dischtime, mc.admittime, DAY) AS los,
    mc.hospital_expire_flag,
    rf.thirty_day_readmission,
    NTILE(3) OVER (ORDER BY mc.med_complexity_score_7day) AS tertile
  FROM medication_complexity mc
  JOIN readmission_flag rf
    ON mc.hadm_id = rf.hadm_id
)

SELECT
  tertile,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(thirty_day_readmission) AS thirty_day_readmission_rate,
  COUNT(*) AS cohort_size
FROM final_cohort
WHERE med_complexity_score_7day IS NOT NULL
GROUP BY tertile
ORDER BY tertile;