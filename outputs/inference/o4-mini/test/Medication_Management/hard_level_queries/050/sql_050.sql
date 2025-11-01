WITH cohort_aki AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      ON a.subject_id = di.subject_id
     AND a.hadm_id = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
      ON di.icd_code = dicd.icd_code
     AND di.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND LOWER(dicd.long_title) LIKE '%acute kidney injury%'
),
meds AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS med_complexity,
    MAX(IF(drug IN ('midazolam','lorazepam','diazepam','morphine','fentanyl','alprazolam'), 1, 0)) AS has_cns,
    MAX(IF(drug IN ('vancomycin','gentamicin','amikacin','ibuprofen','naproxen'), 1, 0)) AS has_neph
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY
    hadm_id
),
joined AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.los_days,
    c.hospital_expire_flag,
    COALESCE(m.med_complexity, 0) AS med_complexity,
    COALESCE(m.has_cns, 0)        AS has_cns,
    COALESCE(m.has_neph, 0)       AS has_neph,
    IF(COALESCE(m.has_cns, 0)=1 AND COALESCE(m.has_neph, 0)=1,
       'both_cns_neph', 'other_aki') AS group_flag
  FROM
    cohort_aki AS c
    LEFT JOIN meds AS m
      ON c.hadm_id = m.hadm_id
),
stats AS (
  SELECT
    group_flag,
    APPROX_QUANTILES(med_complexity, 4)     AS complexity_quarts,
    AVG(med_complexity)                     AS mean_complexity,
    AVG(los_days)                           AS mean_los,
    SUM(hospital_expire_flag)/COUNT(*)      AS mort_rate,
    APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS los_75
  FROM
    joined
  GROUP BY
    group_flag
),
top_quartile AS (
  SELECT
    j.group_flag,
    COUNT(*)                             AS n_top_q,
    AVG(j.los_days)                      AS mean_los_top,
    SUM(j.hospital_expire_flag)/COUNT(*) AS mort_rate_top
  FROM
    joined AS j
    JOIN stats AS s
      ON j.group_flag = s.group_flag
  WHERE
    j.los_days >= s.los_75
  GROUP BY
    j.group_flag
)
SELECT
  s.group_flag,
  s.complexity_quarts       AS med_complexity_quartiles,
  s.mean_complexity,
  s.mean_los                AS overall_mean_los,
  s.mort_rate               AS overall_mortality_rate,
  t.mean_los_top            AS top_quartile_mean_los,
  t.mort_rate_top           AS top_quartile_mortality_rate
FROM
  stats AS s
  LEFT JOIN top_quartile AS t
    ON s.group_flag = t.group_flag
ORDER BY
  s.group_flag;