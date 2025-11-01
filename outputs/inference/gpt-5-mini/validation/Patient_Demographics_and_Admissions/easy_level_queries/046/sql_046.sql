WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    COALESCE(a.hospital_expire_flag, 0) AS hospital_expire_flag,
    p.gender,
    p.anchor_age,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
medications_union AS (
  -- prescriptions
  SELECT
    subject_id,
    hadm_id,
    UPPER(drug) AS med_name,
    'prescriptions' AS source,
    starttime,
    stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    hadm_id IS NOT NULL
    AND drug IS NOT NULL

  UNION ALL

  -- pharmacy
  SELECT
    subject_id,
    hadm_id,
    UPPER(medication) AS med_name,
    'pharmacy' AS source,
    starttime,
    stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE
    hadm_id IS NOT NULL
    AND medication IS NOT NULL

  UNION ALL

  -- emar (administrations)
  SELECT
    subject_id,
    hadm_id,
    UPPER(medication) AS med_name,
    'emar' AS source,
    charttime AS starttime,
    NULL AS stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE
    hadm_id IS NOT NULL
    AND medication IS NOT NULL
),
meds_in_first_adm AS (
  -- keep only meds that belong to the first admission of the selected patients
  SELECT
    m.subject_id,
    m.hadm_id,
    m.med_name
  FROM
    medications_union m
  JOIN
    first_admissions fa
  ON
    m.subject_id = fa.subject_id
    AND m.hadm_id = fa.hadm_id
  WHERE
    fa.rn = 1
),
hadm_med_flags AS (
  -- for each first-hadm, flag presence of aspirin and P2Y12 agents
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN med_name LIKE '%ASPIRIN%' THEN 1 ELSE 0 END) AS has_aspirin,
    MAX(CASE
        WHEN med_name LIKE '%CLOPIDOGREL%' THEN 1
        WHEN med_name LIKE '%PLAVIX%' THEN 1
        WHEN med_name LIKE '%TICAGRELOR%' THEN 1
        WHEN med_name LIKE '%BRILINTA%' THEN 1
        WHEN med_name LIKE '%PRASUGREL%' THEN 1
        WHEN med_name LIKE '%EFFIENT%' THEN 1
        WHEN med_name LIKE '%CANGRELOR%' THEN 1
        ELSE 0
      END) AS has_p2y12
  FROM
    meds_in_first_adm
  GROUP BY
    subject_id,
    hadm_id
),
dapt_first_adm AS (
  -- select only first admissions where both aspirin and P2Y12 were given
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
  JOIN
    hadm_med_flags mf
  USING(subject_id, hadm_id)
  WHERE
    fa.rn = 1
    AND mf.has_aspirin = 1
    AND mf.has_p2y12 = 1
)

SELECT
  COUNT(*) AS n_patients,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS inhospital_mortality_rate,
  STDDEV_POP(CAST(hospital_expire_flag AS FLOAT64)) AS sd_inhospital_mortality
FROM
  dapt_first_adm;