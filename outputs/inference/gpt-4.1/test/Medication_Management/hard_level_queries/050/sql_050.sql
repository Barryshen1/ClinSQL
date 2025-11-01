WITH aki_patients AS (
  -- Female inpatients age 81-91 with AKI
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND (
      -- AKI ICD-10: N17*, ICD-9: 584*
      (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
      OR (dx.icd_version = 9 AND dx.icd_code LIKE '584%')
    )
),

aki_first_adm AS (
  -- Only first AKI admission per patient
  SELECT
    subject_id,
    MIN(hadm_id) AS hadm_id
  FROM aki_patients
  GROUP BY subject_id
),

aki_cohort AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.anchor_age,
    p.gender,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag,
    DATETIME_DIFF(p.dischtime, p.admittime, HOUR)/24.0 AS los
  FROM aki_patients p
  JOIN aki_first_adm fa
    ON p.subject_id = fa.subject_id AND p.hadm_id = fa.hadm_id
  WHERE
    p.dischtime IS NOT NULL
    AND p.admittime IS NOT NULL
),

drug_exposure AS (
  -- For each AKI admission, flag CNS-depressant and nephrotoxic drug exposure
  SELECT
    pr.subject_id,
    pr.hadm_id,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%diazepam%' OR LOWER(pr.drug) LIKE '%lorazepam%' OR LOWER(pr.drug) LIKE '%midazolam%' OR LOWER(pr.drug) LIKE '%alprazolam%' OR LOWER(pr.drug) LIKE '%clonazepam%' OR LOWER(pr.drug) LIKE '%oxazepam%' OR LOWER(pr.drug) LIKE '%temazepam%' OR LOWER(pr.drug) LIKE '%zolpidem%' OR LOWER(pr.drug) LIKE '%phenobarbital%' OR LOWER(pr.drug) LIKE '%propofol%' OR LOWER(pr.drug) LIKE '%fentanyl%' OR LOWER(pr.drug) LIKE '%morphine%' OR LOWER(pr.drug) LIKE '%hydromorphone%' OR LOWER(pr.drug) LIKE '%oxycodone%' OR LOWER(pr.drug) LIKE '%hydrocodone%' OR LOWER(pr.drug) LIKE '%tramadol%' OR LOWER(pr.drug) LIKE '%haloperidol%' OR LOWER(pr.drug) LIKE '%quetiapine%' OR LOWER(pr.drug) LIKE '%olanzapine%' OR LOWER(pr.drug) LIKE '%risperidone%' THEN 1 ELSE 0 END) AS has_cns_depressant,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%gentamicin%' OR LOWER(pr.drug) LIKE '%tobramycin%' OR LOWER(pr.drug) LIKE '%amikacin%' OR LOWER(pr.drug) LIKE '%vancomycin%' OR LOWER(pr.drug) LIKE '%ibuprofen%' OR LOWER(pr.drug) LIKE '%naproxen%' OR LOWER(pr.drug) LIKE '%ketorolac%' OR LOWER(pr.drug) LIKE '%diclofenac%' OR LOWER(pr.drug) LIKE '%celecoxib%' OR LOWER(pr.drug) LIKE '%aspirin%' OR LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%enalapril%' OR LOWER(pr.drug) LIKE '%ramipril%' OR LOWER(pr.drug) LIKE '%captopril%' OR LOWER(pr.drug) LIKE '%fosinopril%' OR LOWER(pr.drug) LIKE '%quinapril%' OR LOWER(pr.drug) LIKE '%perindopril%' OR LOWER(pr.drug) LIKE '%contrast%' OR LOWER(pr.drug) LIKE '%radiocontrast%' THEN 1 ELSE 0 END) AS has_nephrotoxic
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN aki_cohort ac
      ON pr.subject_id = ac.subject_id AND pr.hadm_id = ac.hadm_id
  GROUP BY pr.subject_id, pr.hadm_id
),

complexity_score AS (
  -- For each AKI admission, count unique drugs prescribed
  SELECT
    pr.subject_id,
    pr.hadm_id,
    COUNT(DISTINCT LOWER(pr.drug)) AS med_complexity
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN aki_cohort ac
      ON pr.subject_id = ac.subject_id AND pr.hadm_id = ac.hadm_id
  GROUP BY pr.subject_id, pr.hadm_id
),

aki_final AS (
  -- Merge cohort, drug exposure, and complexity
  SELECT
    ac.subject_id,
    ac.hadm_id,
    ac.anchor_age,
    ac.gender,
    ac.los,
    ac.hospital_expire_flag,
    de.has_cns_depressant,
    de.has_nephrotoxic,
    cs.med_complexity,
    CASE
      WHEN de.has_cns_depressant = 1 AND de.has_nephrotoxic = 1 THEN 'CNS+Nephrotoxic'
      ELSE 'Other AKI'
    END AS group_type
  FROM aki_cohort ac
    LEFT JOIN drug_exposure de
      ON ac.subject_id = de.subject_id AND ac.hadm_id = de.hadm_id
    LEFT JOIN complexity_score cs
      ON ac.subject_id = cs.subject_id AND ac.hadm_id = cs.hadm_id
)

-- Compute quartiles and means for complexity, LOS, and mortality for each group
, stats AS (
  SELECT
    group_type,
    COUNT(*) AS n_patients,
    -- Medication complexity score stats
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(1)] AS complexity_q1,
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(2)] AS complexity_median,
    APPROX_QUANTILES(med_complexity, 4)[OFFSET(3)] AS complexity_q3,
    AVG(med_complexity) AS complexity_mean,
    -- LOS stats
    APPROX_QUANTILES(los, 4)[OFFSET(1)] AS los_q1,
    APPROX_QUANTILES(los, 4)[OFFSET(2)] AS los_median,
    APPROX_QUANTILES(los, 4)[OFFSET(3)] AS los_q3,
    AVG(los) AS los_mean,
    -- Mortality
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM aki_final
  GROUP BY group_type
),

-- Top quartile by complexity per group
top_quartile AS (
  SELECT
    af.*
  FROM aki_final af
    JOIN (
      SELECT
        group_type,
        APPROX_QUANTILES(med_complexity, 4)[OFFSET(3)] AS complexity_q3
      FROM aki_final
      GROUP BY group_type
    ) tq
      ON af.group_type = tq.group_type
      AND af.med_complexity >= tq.complexity_q3
)

, top_stats AS (
  SELECT
    group_type,
    COUNT(*) AS n_patients_top_quartile,
    AVG(los) AS los_mean_top_quartile,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate_top_quartile
  FROM top_quartile
  GROUP BY group_type
)

SELECT
  s.group_type,
  s.n_patients,
  s.complexity_q1,
  s.complexity_median,
  s.complexity_q3,
  s.complexity_mean,
  s.los_q1,
  s.los_median,
  s.los_q3,
  s.los_mean,
  s.mortality_rate,
  ts.n_patients_top_quartile,
  ts.los_mean_top_quartile,
  ts.mortality_rate_top_quartile
FROM stats s
LEFT JOIN top_stats ts
  ON s.group_type = ts.group_type
ORDER BY s.group_type;