WITH hf_patients AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    p.gender,
    p.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
    AND (
      (dx.icd_version = 9  AND dx.icd_code LIKE '428%') OR
      (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
    )
),
cci AS (
  SELECT
    hadm_id,
    subject_id,
    COUNT(DISTINCT comorbidity) AS comorbidity_count
  FROM (
    SELECT
      d.hadm_id,
      d.subject_id,
      CASE
        WHEN (d.icd_version = 9  AND d.icd_code BETWEEN '25000' AND '25093') OR
             (d.icd_version = 10 AND d.icd_code LIKE 'E10%') OR
             (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          THEN 'Diabetes'
        WHEN (d.icd_version = 9  AND d.icd_code LIKE '585%') OR
             (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
          THEN 'Chronic kidney disease'
        WHEN (d.icd_version = 9  AND d.icd_code LIKE '414%') OR
             (d.icd_version = 10 AND d.icd_code LIKE 'I25%')
          THEN 'Coronary artery disease'
        WHEN (d.icd_version = 9  AND d.icd_code LIKE '401%') OR
             (d.icd_version = 10 AND d.icd_code LIKE 'I10%')
          THEN 'Hypertension'
        WHEN (d.icd_version = 9  AND d.icd_code LIKE '162%') OR
             (d.icd_version = 10 AND d.icd_code LIKE 'C34%')
          THEN 'Cancer'
        -- Add further Charlson categories mapping here
      END AS comorbidity
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ) m
  WHERE comorbidity IS NOT NULL
  GROUP BY hadm_id, subject_id
),
icu_flag AS (
  SELECT DISTINCT
    hadm_id,
    1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
merged AS (
  SELECT
    hfp.subject_id,
    hfp.hadm_id,
    CASE WHEN icu.icu_flag = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_group,
    DATE_DIFF(hfp.dischtime, hfp.admittime, DAY) AS los_days,
    CASE
      WHEN DATE_DIFF(hfp.dischtime, hfp.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATE_DIFF(hfp.dischtime, hfp.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_cat,
    IFNULL(c.comorbidity_count,0) AS comorbidity_count,
    CASE
      WHEN IFNULL(c.comorbidity_count,0) <= 3 THEN '<=3'
      WHEN IFNULL(c.comorbidity_count,0) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS cci_cat,
    hfp.hospital_expire_flag
  FROM hf_patients hfp
  LEFT JOIN cci c
    ON hfp.hadm_id = c.hadm_id
  LEFT JOIN icu_flag icu
    ON hfp.hadm_id = icu.hadm_id
)
SELECT
  icu_group,
  los_cat,
  cci_cat,
  COUNT(*) AS n,
  100*AVG(hospital_expire_flag) AS mortality_pct,
  -- 95% CI for proportion
  100*(AVG(hospital_expire_flag) - 1.96*SQRT(AVG(hospital_expire_flag)*(1-AVG(hospital_expire_flag))/COUNT(*))) AS mortality_pct_lci,
  100*(AVG(hospital_expire_flag) + 1.96*SQRT(AVG(hospital_expire_flag)*(1-AVG(hospital_expire_flag))/COUNT(*))) AS mortality_pct_uci,
  AVG(comorbidity_count) AS mean_comorbidity_count
FROM merged
GROUP BY icu_group, los_cat, cci_cat
ORDER BY icu_group, los_cat, cci_cat;