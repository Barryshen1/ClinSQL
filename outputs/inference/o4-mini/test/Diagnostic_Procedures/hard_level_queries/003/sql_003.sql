WITH icu_base AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ad.admittime,
    ad.dischtime,
    ad.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    USING(subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
),
ards_flag AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%acute respiratory distress syndrome%'
),
proc_24h AS (
  SELECT
    pe.stay_id,
    COUNT(DISTINCT pe.itemid) AS intensity
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN icu_base ib
    ON pe.subject_id = ib.subject_id
   AND pe.hadm_id    = ib.hadm_id
   AND pe.stay_id    = ib.stay_id
  WHERE pe.starttime BETWEEN ib.intime
                       AND TIMESTAMP_ADD(ib.intime, INTERVAL 24 HOUR)
  GROUP BY pe.stay_id
),
cohort_data AS (
  SELECT
    ib.stay_id,
    ib.admittime,
    ib.dischtime,
    ib.hospital_expire_flag,
    p24.intensity,
    CASE
      WHEN ib.gender = 'F'
       AND ib.anchor_age BETWEEN 84 AND 94
       AND EXISTS (
         SELECT 1
         FROM ards_flag af
         WHERE af.subject_id = ib.subject_id
           AND af.hadm_id    = ib.hadm_id
       )
      THEN 'ARDS F 84-94'
      ELSE 'All ICU'
    END AS cohort
  FROM icu_base ib
  LEFT JOIN proc_24h p24
    ON ib.stay_id = p24.stay_id
)
SELECT
  cohort,
  APPROX_QUANTILES(intensity, 100)[OFFSET(25)] AS p25_intensity,
  APPROX_QUANTILES(intensity, 100)[OFFSET(75)] AS p75_intensity,
  APPROX_QUANTILES(intensity, 100)[OFFSET(95)] AS p95_intensity,
  ROUND(AVG(DATE_DIFF(dischtime, admittime, DAY)), 2) AS avg_los_days,
  ROUND(AVG(hospital_expire_flag), 3)               AS avg_hospital_mortality
FROM cohort_data
GROUP BY cohort
ORDER BY cohort;