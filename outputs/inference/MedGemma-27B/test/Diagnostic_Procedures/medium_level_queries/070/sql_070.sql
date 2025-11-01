WITH PatientCohort AS (
  SELECT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 64
),
DiagnosisCohort AS (
  SELECT DISTINCT
    d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    d.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
    AND di.long_title LIKE '%heart failure%'
),
AdmissionCohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM DiagnosisCohort
    )
),
RadiographyEvents AS (
  SELECT
    a.hadm_id,
    COUNT(r.hcpcs_cd) AS radiography_count
  FROM AdmissionCohort AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS r
    ON a.hadm_id = r.hadm_id
  WHERE
    r.hcpcs_cd LIKE '7%' -- Radiography/CT codes start with 7
  GROUP BY
    a.hadm_id
),
AdmissionLength AS (
  SELECT
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL
      THEN TIMESTAMP_DIFF(deathtime, admittime, DAY)
      ELSE TIMESTAMP_DIFF(dischtime, admittime, DAY)
    END AS los_days
  FROM AdmissionCohort
),
ICUUse AS (
  SELECT DISTINCT
    a.hadm_id,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM `physionet-data.mimiciv_3_1_icu.icustays` AS i
        WHERE
          i.hadm_id = a.hadm_id
      )
      THEN 1
      ELSE 0
    END AS icu_used
  FROM AdmissionCohort AS a
),
CombinedData AS (
  SELECT
    r.hadm_id,
    r.radiography_count,
    al.los_days,
    iu.icu_used
  FROM RadiographyEvents AS r
  JOIN AdmissionLength AS al
    ON r.hadm_id = al.hadm_id
  JOIN ICUUse AS iu
    ON r.hadm_id = iu.hadm_id
)
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN los_days BETWEEN 5 AND 8
    THEN '5-8 days'
    ELSE 'Other'
  END AS los_group,
  icu_used,
  APPROX_QUANTILES(radiography_count, [0.25, 0.50, 0.75]) AS quantiles
FROM CombinedData
WHERE
  los_days NOT IN (0, 1) -- Exclude 0 or 1 day stays
GROUP BY
  los_group,
  icu_used;