WITH aki_patients AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, pat.anchor_age, pat.gender,
    adm.admittime, adm.dischtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND (
      (dx.icd_version = 9  AND dx.icd_code LIKE '584%')
      OR
      (dx.icd_version = 10 AND dx.icd_code LIKE 'N17%')
    )
),
drug_exposures AS (
  SELECT p.subject_id, p.hadm_id,
    COUNT(DISTINCT LOWER(drug)) AS med_complexity,
    /* Boolean flags for drug classes */
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(drug), r"(morphine|fentanyl|midazolam|lorazepam|diazepam|propofol|oxycodone|hydromorphone|clonazepam|phenobarb|gabapentin|pregabalin)") THEN 1 ELSE 0 END) AS has_cns_dep,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(drug), r"(vancomycin|gentamicin|amikacin|tobramycin|amphotericin|acyclovir|ibuprofen|naproxen|ketorolac|cisplatin|contrast)") THEN 1 ELSE 0 END) AS has_nephrotox
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  /* Filter only to AKI cohort HADM_IDs */
  JOIN aki_patients ak
    ON p.subject_id = ak.subject_id AND p.hadm_id = ak.hadm_id
  GROUP BY p.subject_id, p.hadm_id
),
cohort AS (
  SELECT ak.subject_id, ak.hadm_id, ak.admittime, ak.dischtime,
    DATETIME_DIFF(ak.dischtime, ak.admittime, HOUR)/24.0 AS los_days,
    ak.hospital_expire_flag,
    de.med_complexity,
    de.has_cns_dep,
    de.has_nephrotox,
    CASE WHEN de.has_cns_dep = 1 AND de.has_nephrotox = 1
         THEN 'AKI + CNS & Nephrotoxic'
         ELSE 'AKI other'
    END AS group_flag
  FROM aki_patients ak
  JOIN drug_exposures de
    ON ak.subject_id = de.subject_id AND ak.hadm_id = de.hadm_id
),
quartiles AS (
  SELECT group_flag,
    APPROX_QUANTILES(med_complexity, 4) AS qs,
    AVG(med_complexity) AS mean_complexity
  FROM cohort
  GROUP BY group_flag
),
cohort_with_qs AS (
  SELECT c.*,
         q.qs[OFFSET(1)] AS q1,
         q.qs[OFFSET(2)] AS median,
         q.qs[OFFSET(3)] AS q3,
         q.mean_complexity
  FROM cohort c
  JOIN quartiles q
    ON c.group_flag = q.group_flag
),
summary AS (
  SELECT group_flag,
         mean_complexity,
         q1, median, q3,
         COUNT(*) AS n_patients,
         AVG(los_days) AS mean_los,
         AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort_with_qs
  GROUP BY group_flag, mean_complexity, q1, median, q3
),
top_quartile_outcomes AS (
  SELECT group_flag,
         COUNT(*) AS n_topq,
         AVG(los_days) AS mean_los_topq,
         AVG(hospital_expire_flag) AS mortality_rate_topq
  FROM cohort_with_qs
  WHERE med_complexity >= q3
  GROUP BY group_flag
)
SELECT s.group_flag,
       s.n_patients,
       s.mean_complexity,
       s.q1, s.median, s.q3,
       s.mean_los,
       s.mortality_rate,
       t.n_topq,
       t.mean_los_topq,
       t.mortality_rate_topq
FROM summary s
LEFT JOIN top_quartile_outcomes t
  ON s.group_flag = t.group_flag
ORDER BY s.group_flag;