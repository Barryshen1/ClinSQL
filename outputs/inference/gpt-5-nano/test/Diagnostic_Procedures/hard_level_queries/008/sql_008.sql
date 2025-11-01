WITH ugib_stays AS (
  SELECT
    I.subject_id,
    I.hadm_id,
    I.stay_id,
    I.intime,
    -- Compute hospital LOS in days using TIMESTAMP_DIFF with proper casts
    TIMESTAMP_DIFF(TIMESTAMP(H.dischtime), TIMESTAMP(H.admittime), SECOND) / 86400.0 AS hospital_los_days,
    -- Mortality indicator as 0/1
    CAST(H.hospital_expire_flag AS INT64) AS in_hospital_mortality
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS I
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS H
    ON I.hadm_id = H.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS DI
    ON DI.subject_id = I.subject_id AND DI.hadm_id = I.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS DCD
    ON DCD.icd_code = DI.icd_code AND DCD.icd_version = DI.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS P
    ON P.subject_id = I.subject_id
  WHERE P.gender = 'M'
    AND P.anchor_age BETWEEN 48 AND 58
    AND (
      LOWER(DCD.long_title) LIKE '%upper%'
      OR LOWER(DCD.long_title) LIKE '%gastric%'
      OR LOWER(DCD.long_title) LIKE '%duodenum%'
      OR LOWER(DI.icd_code) LIKE '578%'
    )
),
per_stay AS (
  SELECT
    U.subject_id,
    U.hadm_id,
    U.stay_id,
    U.intime,
    U.hospital_los_days,
    U.in_hospital_mortality,
    SUM(
      CASE
        WHEN di.category = 'Diagnostic'
             AND PE.starttime BETWEEN U.intime AND TIMESTAMP_ADD(U.intime, INTERVAL 24 HOUR)
        THEN 1
        ELSE 0
      END
    ) AS first24_diag_proc
  FROM ugib_stays AS U
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` AS PE
    ON PE.stay_id = U.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = PE.itemid
  GROUP BY
    U.subject_id,
    U.hadm_id,
    U.stay_id,
    U.intime,
    U.hospital_los_days,
    U.in_hospital_mortality
)
SELECT quintile,
       AVG(first24_diag_proc) AS avg_first24_diag_proc,
       AVG(hospital_los_days) AS avg_hospital_los_days,
       SAFE_DIVIDE(SUM(in_hospital_mortality), COUNT(*)) * 100 AS in_hospital_mortality_percent
FROM (
  SELECT *,
         NTILE(5) OVER (ORDER BY first24_diag_proc) AS quintile
  FROM per_stay
) AS t
GROUP BY quintile
ORDER BY quintile;