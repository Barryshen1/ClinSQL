WITH PatientHF AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d.icd_code LIKE 'I50%' -- Heart failure codes
),
AdmissionImaging AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime, -- Corrected column name
    a.dischtime,
    h.hcpcs_cd,
    h.short_description
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
    ON a.hadm_id = h.hadm_id
  WHERE
    h.hcpcs_cd LIKE '7%' -- Imaging codes
),
AdmissionLOS AS (
  SELECT
    hadm_id,
    -- Calculate LOS in days
    (TIMESTAMP_DIFF(dischtime, admitime, DAY) + 1) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),
AdmissionHFType AS (
  SELECT
    hadm_id,
    -- Determine primary vs secondary HF
    CASE
      WHEN seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS hf_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    icd_code LIKE 'I50%'
)
SELECT
  a.hf_type,
  CASE
    WHEN a.los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN a.los BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Other'
  END AS los_group,
  PERCENTILE_CONT(a.imaging_count, 0.25) AS p25,
  PERCENTILE_CONT(a.imaging_count, 0.50) AS p50,
  PERCENTILE_CONT(a.imaging_count, 0.75) AS p75
FROM
  (
    SELECT
      phf.subject_id,
      a.hadm_id,
      ahf.hf_type,
      al.los,
      COUNT(ai.hcpcs_cd) AS imaging_count
    FROM
      PatientHF AS phf
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON phf.subject_id = a.subject_id
    INNER JOIN
      AdmissionImaging AS ai
      ON a.hadm_id = ai.hadm_id
    INNER JOIN
      AdmissionLOS AS al
      ON a.hadm_id = al.hadm_id
    INNER JOIN
      AdmissionHFType AS ahf
      ON a.hadm_id = ahf.hadm_id
    WHERE
      ai.hcpcs_cd LIKE '7%' -- Filter for imaging codes
    GROUP BY
      phf.subject_id,
      a.hadm_id,
      ahf.hf;