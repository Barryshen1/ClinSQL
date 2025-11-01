WITH
  charlson_components AS (
    SELECT
      hadm_id,
      -- Map ICD codes to Charlson conditions, excluding Congestive Heart Failure
      CASE
        WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) IN ('410', '412') THEN 'MI'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') OR SUBSTR(icd_code, 1, 5) = 'I25.2') THEN 'MI'
        WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 4) IN ('4439', '7854', 'V434') OR SUBSTR(icd_code, 1, 3) = '441') THEN 'PVD'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'I70' AND 'I73' OR SUBSTR(icd_code, 1, 4) = 'I771') THEN 'PVD'
        WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '430' AND '438' THEN 'CVD'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('G45', 'G46') OR SUBSTR(icd_code, 1, 3) BETWEEN 'I60' AND 'I69' OR SUBSTR(icd_code, 1, 5) = 'H34.0') THEN 'CVD'
        WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '290' OR SUBSTR(icd_code, 1, 5) IN ('29410', '29411', '3312')) THEN 'DEMENTIA'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('F00', 'F01', 'F02', 'F03', 'G30') OR SUBSTR(icd_code, 1, 4) = 'G311') THEN 'DEMENTIA'
        WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '490' AND '508' AND SUBSTR(icd_code, 1, 4) != '5070') THEN 'CPD'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'J40' AND 'J47' OR SUBSTR(icd_code, 1, 3) BETWEEN 'J60' AND 'J67') THEN 'CPD'
        WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) = '710' OR SUBSTR(icd_code, 1, 4) IN ('7140', '7141', '7142', '7148')) THEN 'RHEUM'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('M05', 'M06', 'M32', 'M33', 'M34') OR SUBSTR(icd_code, 1, 4) = 'M315') THEN 'RHEUM'
        WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '531' AND '534' THEN 'PUD'
        WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'K25' AND 'K28' THEN 'PUD'
        WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('5712', '5715', '5716') THEN 'MILD_LIVER'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) = 'B18' OR SUBSTR(icd_code, 1, 4) IN ('K700', 'K701', 'K702', 'K703', 'K709') OR SUBSTR(icd_code, 1, 3) IN ('K73', 'K74') OR SUBSTR(icd_code, 1, 4) = 'K717') THEN 'MILD_LIVER'
        WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) BETWEEN '2500' AND '2503' THEN 'DIAB_UNCOMP'
        WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E10', 'E11', 'E12', 'E13', 'E14') AND SUBSTR(icd_code, 5, 1) IN ('0', '1', '6', '8', '9') THEN 'DIAB_UNCOMP'
        WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) BETWEEN '2504' AND '2509' THEN 'DIAB_COMP'
        WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E10', 'E11', 'E12', 'E13', 'E14') AND SUBSTR(icd_code, 5, 1) IN ('2', '3', '4', '5', '7') THEN 'DIAB_COMP'
        WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 4) = '3441' OR SUBSTR(icd_code, 1, 3) = '342') THEN 'PLEGIA'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('G81', 'G82') OR SUBSTR(icd_code, 1, 4) = 'G041') THEN 'PLEGIA'
        WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) IN ('582', '583', '585', '586') OR SUBSTR(icd_code, 1, 4) IN ('V420', 'V451') OR SUBSTR(icd_code, 1, 3) = 'V56') THEN 'RENAL'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('N18', 'N19', 'N25') OR SUBSTR(icd_code, 1, 4) IN ('Z490', 'Z491', 'Z492', 'Z992')) THEN 'RENAL'
        WHEN icd_version = 9 AND (SUBSTR(icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(icd_code, 1, 3) BETWEEN '174' AND '195' OR SUBSTR(icd_code, 1, 3) BETWEEN '200' AND '208') THEN 'MALIGNANCY'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 3) BETWEEN 'C00' AND 'C76' OR SUBSTR(icd_code, 1, 3) BETWEEN 'C81' AND 'C97') THEN 'MALIGNANCY'
        WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 4) IN ('5722', '5723', '5724') THEN 'SEVERE_LIVER'
        WHEN icd_version = 10 AND (SUBSTR(icd_code, 1, 4) IN ('K721', 'K729') OR SUBSTR(icd_code, 1, 4) BETWEEN 'K765' AND 'K767') THEN 'SEVERE_LIVER'
        WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) BETWEEN '196' AND '199' THEN 'METS'
        WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'C77' AND 'C80' THEN 'METS'
        WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '042' THEN 'HIV'
        WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) BETWEEN 'B20' AND 'B24' THEN 'HIV'
        ELSE NULL
      END AS condition
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  ),
  comorbidity_scores AS (
    SELECT
      hadm_id,
      (
        MAX(CASE WHEN condition = 'MI' THEN 1 ELSE 0 END)
        + MAX(CASE WHEN condition = 'PVD' THEN 1 ELSE 0 END)
        + MAX(CASE WHEN condition = 'CVD' THEN 1 ELSE 0 END)
        + MAX(CASE WHEN condition = 'DEMENTIA' THEN 1 ELSE 0 END)
        + MAX(CASE WHEN condition = 'CPD' THEN 1 ELSE 0 END)
        + MAX(CASE WHEN condition = 'RHEUM' THEN 1 ELSE 0 END)
        + MAX(CASE WHEN condition = 'PUD' THEN 1 ELSE 0 END)
        + MAX(CASE WHEN condition = 'MILD_LIVER' THEN 1 WHEN condition = 'SEVERE_LIVER' THEN 3 ELSE 0 END) -- Liver disease
        + MAX(CASE WHEN condition = 'DIAB_UNCOMP' THEN 1 WHEN condition = 'DIAB_COMP' THEN 2 ELSE 0 END) -- Diabetes
        + MAX(CASE WHEN condition = 'PLEGIA' THEN 2 ELSE 0 END)
        + MAX(CASE WHEN condition = 'RENAL' THEN 2 ELSE 0 END)
        + MAX(CASE WHEN condition = 'MALIGNANCY' THEN 2 WHEN condition = 'METS' THEN 6 ELSE 0 END) -- Malignancy
        + MAX(CASE WHEN condition = 'HIV' THEN 6 ELSE 0 END)
      ) AS charlson_score,
      MAX(CASE WHEN condition LIKE 'DIAB%' THEN 1 ELSE 0 END) AS is_diabetes,
      MAX(CASE WHEN condition = 'RENAL' THEN 1 ELSE 0 END) AS is_ckd
    FROM charlson_components
    GROUP BY hadm_id
  ),
  base_cohort AS (
    SELECT DISTINCT p.subject_id, dx.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON p.subject_id = dx.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age BETWEEN 39 AND 49
      AND (
        (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
        OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
      )
  ),
  final_cohort_data AS (
    SELECT
      a.hadm_id,
      a.hospital_expire_flag,
      COALESCE(cs.charlson_score, 0) AS charlson_score,
      COALESCE(cs.is_diabetes, 0) AS is_diabetes,
      COALESCE(cs.is_ckd, 0) AS is_ckd,
      CASE
        WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) <= 5 THEN '≤5 days'
        ELSE '>5 days'
      END AS los_group,
      NTILE(3) OVER (ORDER BY COALESCE(cs.charlson_score, 0)) AS comorbidity_tertile_num
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN base_cohort AS bc
      ON a.hadm_id = bc.hadm_id
    LEFT JOIN comorbidity_scores AS cs
      ON a.hadm_id = cs.hadm_id
  )
SELECT
  los_group,
  CASE
    WHEN comorbidity_tertile_num = 1 THEN 'Low'
    WHEN comorbidity_tertile_num = 2 THEN 'Med'
    WHEN comorbidity_tertile_num = 3 THEN 'High'
  END AS comorbidity_tertile,
  COUNT(hadm_id) AS N,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_pct,
  ROUND(AVG(is_ckd) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(is_diabetes) * 100, 2) AS diabetes_prevalence_pct
FROM final_cohort_data
GROUP BY
  los_group,
  comorbidity_tertile_num
ORDER BY
  los_group,
  comorbidity_tertile_num;