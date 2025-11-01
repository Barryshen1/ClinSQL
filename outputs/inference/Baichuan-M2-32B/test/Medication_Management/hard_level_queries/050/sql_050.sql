WITH eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 81 AND 91
),
aki_patients AS (
  SELECT
    ep.*
  FROM
    eligible_patients ep
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ep.subject_id = di.subject_id AND ep.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    d.icd_version = 10
    AND d.icd_code LIKE 'N17%'
  GROUP BY
    ep.subject_id, ep.hadm_id, ep.admittime, ep.dischtime, ep.hospital_expire_flag, ep.age_at_admission
),
cns_depressants AS (
  SELECT 'diazepam' AS drug
  UNION ALL SELECT 'lorazepam'
  UNION ALL SELECT 'morphine'
  UNION ALL SELECT 'fentanyl'
  UNION ALL SELECT 'haloperidol'
  UNION ALL SELECT 'clonazepam'
  UNION ALL SELECT 'oxycodone'
  UNION ALL SELECT 'hydromorphone'
  UNION ALL SELECT 'midazolam'
),
nephrotoxins AS (
  SELECT 'gentamicin' AS drug
  UNION ALL SELECT 'vancomycin'
  UNION ALL SELECT 'amikacin'
  UNION ALL SELECT 'tobramycin'
  UNION ALL SELECT 'contrast media'
  UNION ALL SELECT 'cyclosporine'
  UNION ALL SELECT 'aminophylline'
  UNION ALL SELECT 'cisplatin'
),
medications AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.drug,
    CASE WHEN LOWER(p.drug) IN (SELECT drug FROM cns_depressants) THEN 1 ELSE 0 END AS is_cns_depressant,
    CASE WHEN LOWER(p.drug) IN (SELECT drug FROM nephrotoxins) THEN 1 ELSE 0 END AS is_nephrotoxic
  FROM
    aki_patients a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id
),
admission_drugs AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(is_cns_depressant) AS has_cns_depressant,
    MAX(is_nephrotoxic) AS has_nephrotoxic,
    COUNT(DISTINCT drug) AS distinct_drug_count
  FROM
    medications
  GROUP BY
    subject_id, hadm_id
),
outcomes AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.hospital_expire_flag AS mortality
  FROM
    aki_patients a
),
cohort AS (
  SELECT
    ad.subject_id,
    ad.hadm_id,
    ad.distinct_drug_count AS complexity,
    o.los,
    o.mortality,
    CASE WHEN ad.has_cns_depressant = 1 AND ad.has_nephrotoxic = 1 THEN 1 ELSE 0 END AS has_both_drugs
  FROM
    admission_drugs ad
  JOIN
    outcomes o
    ON ad.subject_id = o.subject_id AND ad.hadm_id = o.hadm_id
),
top_quartile_los AS (
  SELECT
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS top_quartile_los_value
  FROM
    cohort
),
final_metrics AS (
  SELECT
    has_both_drugs AS group_flag,
    APPROX_QUANTILES(complexity, 4) AS complexity_quartiles,
    AVG(complexity) AS mean_complexity,
    AVG(los) AS mean_los,
    AVG(mortality) AS mortality_rate,
    (SELECT top_quartile_los_value FROM top_quartile_los) AS top_quartile_los,
    AVG(CASE WHEN los >= (SELECT top_quartile_los_value FROM top_quartile_los) THEN mortality ELSE NULL END) AS top_quartile_mortality
  FROM
    cohort
  GROUP BY
    has_both_drugs
)
SELECT
  group_flag,
  complexity_quartiles[OFFSET(0)] AS q1_complexity,
  complexity_quartiles[OFFSET(1)] AS q2_complexity,
  complexity_quartiles[OFFSET(2)] AS q3_complexity,
  complexity_quartiles[OFFSET(3)] AS q4_complexity,
  mean_complexity,
  mean_los,
  mortality_rate,
  top_quartile_los,
  top_quartile_mortality
FROM
  final_metrics
ORDER BY
  group_flag;