WITH PostoperativeComplications AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 1
      ELSE 0
    END AS mortality,
    CASE
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 3
      THEN '≤3'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 6
      THEN '4–6'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 7 AND 10
      THEN '7–10'
      ELSE '>10'
    END AS los_category,
    CASE
      WHEN cci.cci <= 3
      THEN '≤3'
      WHEN cci.cci BETWEEN 4 AND 5
      THEN '4–5'
      ELSE '>5'
    END AS cci_category,
    CASE
      WHEN icu.stay_id IS NOT NULL
      THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM procedures_icd AS proc
        WHERE
          proc.subject_id = a.subject_id AND proc.hadm_id = a.hadm_id
      )
      THEN 1
      ELSE 0
    END AS had_surgery,
    CASE
      WHEN EXISTS (
        SELECT
          1
        FROM diagnoses_icd AS diag
        WHERE
          diag.subject_id = a.subject_id AND diag.hadm_id = a.hadm_id AND diag.icd_code LIKE '99%'
      )
      THEN 1
      ELSE 0
    END AS had_complication
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.icustays` AS icu
    ON a.hadm_id = icu.hadm_id
  LEFT JOIN (
    SELECT
      subject_id,
      hadm_id,
      SUM(cci_points) AS cci
    FROM (
      SELECT
        subject_id,
        hadm_id,
        CASE
          WHEN d.icd_code IN ('4280', '4281', '4282', '4283', '4284', '4285', '4286', '4287', '4288', '4289', '4290', '4291', '4292', '4293', '4294', '4295', '4296', '4297', '4298', '4299', '4300', '4310', '4311', '4312', '4313', '4314', '4315', '4316', '4317', '4318', '4319', '4320', '4321', '4322', '4323', '4324', '4325', '4326', '4327', '4328', '4329', '4330', '4331', '4332', '4333', '4334', '4335', '4336', '4337', '4338', '4339', '4340', '4341', '4342', '4343', '4344', '4345', '4346', '4347', ';