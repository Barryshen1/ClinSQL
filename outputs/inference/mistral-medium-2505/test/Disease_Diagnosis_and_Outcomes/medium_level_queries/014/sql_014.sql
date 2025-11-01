WITH hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    MAX(CASE WHEN di.icd_code IN ('4280', '4281', '42820', '42821', '42822', '42823', '42830', '42831', '42832', '42833', '42840', '42841', '42842', '42843', '4289', 'I501', 'I5020', 'I5021', 'I5022', 'I5023', 'I5030', 'I5031', 'I5032', 'I5033', 'I5034', 'I504', 'I509') THEN 1 ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND a.hadm_id IS NOT NULL
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, los_days
  HAVING
    has_hf = 1
),

icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    intime AS first_icu_intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

comorbidities AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN icd_code IN ('5851', '5852', '5853', '5854', '5855', '5856', '5859', 'N181', 'N182', 'N183', 'N184', 'N185', 'N186', 'N189') THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN icd_code IN ('25000', '25001', '25002', '25003', '25010', '25011', '25012', '25013', '25020', '25021', '25022', '25023', '25030', '25031', '25032', '25033', '25040', '25041', '25042', '25043', '25050', '25051', '25052', '25053', '25060', '25061', '25062', '25063', '25070', '25071', '25072', '25073', '25080', '25081', '25082', '25083', '25090', '25091', '25092', '25093', 'E1010', 'E1011', 'E1021', 'E1022', 'E1029', 'E10311', 'E10319', 'E10321', 'E10329', 'E10331', 'E10339', 'E10341', 'E10349', 'E10351', 'E10359', 'E1036', 'E1037', 'E1039', 'E1040', 'E1041', 'E1042', 'E1043', 'E1044', 'E1049', 'E1051', 'E1052', 'E1059', 'E10610', 'E10618', 'E10620', 'E10621', 'E10622', 'E10628', 'E10630', 'E10631', 'E10632', 'E10638', 'E10640', 'E10641', 'E10642', 'E10648', 'E1065', 'E1069', 'E108', 'E109') THEN 1 ELSE 0 END) AS has_diabetes
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    subject_id, hadm_id
)

SELECT
  CASE WHEN i.first_icu_intime IS NOT NULL AND TIMESTAMP_DIFF(i.first_icu_intime, h.admittime, HOUR) <= 24 THEN 'Day-1 ICU' ELSE 'Non-ICU' END AS icu_status,
  CASE
    WHEN h.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN h.los_days BETWEEN 4 AND 7 THEN '4-7 days'
    WHEN h.los_days >= 8 THEN '≥8 days'
    ELSE 'Other'
  END AS los_group,
  COUNT(*) AS admission_count,
  ROUND(100 * SUM(h.hospital_expire_flag) / COUNT(*), 1) AS mortality_percentage,
  ROUND(PERCENTILE_CONT(h.los_days, 0.5), 1) AS median_los,
  ROUND(100 * SUM(c.has_ckd) / COUNT(*), 1) AS ckd_prevalence,
  ROUND(100 * SUM(c.has_diabetes) / COUNT(*), 1) AS diabetes_prevalence
FROM
  hf_admissions h
LEFT JOIN
  icu_stays i ON h.subject_id = i.subject_id AND h.hadm_id = i.hadm_id
LEFT JOIN
  comorbidities c ON h.subject_id = c.subject_id AND h.hadm_id = c.hadm_id
GROUP BY
  icu_status, los_group
ORDER BY
  icu_status, los_group;