WITH surgical_services AS (
  -- Identify surgical admissions by first service
  SELECT
    subject_id,
    hadm_id,
    curr_service,
    transfertime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM physionet-data.mimiciv_3_1_hosp.services
  WHERE curr_service IN (
    'SURG', 'TSURG', 'NSURG', 'VSURG', 'ORTHO', 'CSURG', 'GSURG', 'PSURG', 'OTOL', 'ENT', 'URO', 'PLASTIC', 'CARDIOTHORACIC'
  )
),
surgical_admissions AS (
  -- Cohort: female, age 70-80, surgical, inpatient
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    adm.discharge_location,
    pat.gender,
    pat.anchor_age
  FROM physionet-data.mimiciv_3_1_hosp.admissions adm
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN surgical_services ss
    ON adm.hadm_id = ss.hadm_id AND ss.rn = 1
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 70 AND 80
),
admissions_los AS (
  -- Calculate LOS and discharge group
  SELECT
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'Death'
      WHEN REGEXP_CONTAINS(UPPER(discharge_location), r'HOME') THEN 'Home'
      WHEN REGEXP_CONTAINS(UPPER(discharge_location), r'SNF|SKILLED|REHAB|LTAC|LONG TERM ACUTE CARE|FACILITY|NURSING') THEN 'Facility'
      ELSE 'Other'
    END AS discharge_group
  FROM surgical_admissions
)
SELECT
  discharge_group,
  COUNT(*) AS n_total,
  COUNTIF(los_days >= 7) AS n_LOS_7plus,
  SAFE_DIVIDE(COUNTIF(los_days >= 7), COUNT(*)) AS prop_LOS_7plus,
  COUNTIF(los_days >= 14) AS n_LOS_14plus,
  SAFE_DIVIDE(COUNTIF(los_days >= 14), COUNT(*)) AS prop_LOS_14plus
FROM admissions_los
WHERE discharge_group IN ('Home', 'Facility', 'Death')
GROUP BY discharge_group
ORDER BY discharge_group;