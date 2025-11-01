WITH female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),

diagnosis_flags AS (
  -- Identify sepsis and septic shock per admission
  SELECT
    fa.subject_id,
    fa.hadm_id,
    MAX(CASE
      WHEN (di.icd_version = 9 AND (
        di.icd_code LIKE '99591' OR
        di.icd_code LIKE '99593' OR
        di.icd_code LIKE '038%' -- sepsis
      )) OR (di.icd_version = 10 AND (
        di.icd_code LIKE 'A40%' OR
        di.icd_code LIKE 'A41%' -- sepsis
      ))
      THEN 1 ELSE 0 END) AS has_sepsis,
    MAX(CASE
      WHEN (di.icd_version = 9 AND di.icd_code = '78552') OR
           (di.icd_version = 10 AND di.icd_code = 'R6521')
      THEN 1 ELSE 0 END) AS has_shock
  FROM
    female_admissions fa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON fa.hadm_id = di.hadm_id
  GROUP BY
    fa.subject_id, fa.hadm_id
),

charlson_map AS (
  -- Map ICD codes to Charlson comorbidity categories
  -- Adapted from MIT-LCP charlson.sql (https://github.com/MIT-LCP/mimic-code/blob/main/concepts/comorbidity/charlson.sql)
  SELECT
    di.hadm_id,
    MAX(CASE WHEN
      -- Myocardial infarction
      (di.icd_version = 9 AND di.icd_code IN ('410', '412')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I252%')
      THEN 1 ELSE 0 END) AS mi,
    MAX(CASE WHEN
      -- Congestive heart failure
      (di.icd_version = 9 AND di.icd_code IN ('428', '39891', '40201', '40211', '40291', '40401', '40411', '40491', '4254', '4255', '4257', '4258', '4259')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I50%' OR di.icd_code LIKE 'I110%' OR di.icd_code LIKE 'I130%' OR di.icd_code LIKE 'I132%' OR di.icd_code LIKE 'I255%' OR di.icd_code LIKE 'I420%' OR di.icd_code LIKE 'I425%' OR di.icd_code LIKE 'I426%' OR di.icd_code LIKE 'I427%' OR di.icd_code LIKE 'I428%' OR di.icd_code LIKE 'I429%' OR di.icd_code LIKE 'P290%')
      THEN 1 ELSE 0 END) AS chf,
    MAX(CASE WHEN
      -- Peripheral vascular disease
      (di.icd_version = 9 AND di.icd_code IN ('4439', '441', '4412', '4414', '4417', '4419', '7854', 'V434')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I70%' OR di.icd_code LIKE 'I71%' OR di.icd_code LIKE 'I731%' OR di.icd_code LIKE 'I738%' OR di.icd_code LIKE 'I739%' OR di.icd_code LIKE 'I771%' OR di.icd_code LIKE 'I790%' OR di.icd_code LIKE 'I792%' OR di.icd_code LIKE 'K551%' OR di.icd_code LIKE 'K558%' OR di.icd_code LIKE 'K559%' OR di.icd_code LIKE 'Z958%' OR di.icd_code LIKE 'Z959%')
      THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE WHEN
      -- Cerebrovascular disease
      (di.icd_version = 9 AND di.icd_code IN ('430', '431', '432', '433', '434', '435', '436', '437', '438')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%' OR di.icd_code LIKE 'I63%' OR di.icd_code LIKE 'I64%' OR di.icd_code LIKE 'G45%' OR di.icd_code LIKE 'G46%')
      THEN 1 ELSE 0 END) AS cerebro,
    MAX(CASE WHEN
      -- Dementia
      (di.icd_version = 9 AND di.icd_code IN ('290', '2941', '3312')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'F00%' OR di.icd_code LIKE 'F01%' OR di.icd_code LIKE 'F02%' OR di.icd_code LIKE 'F03%' OR di.icd_code LIKE 'G30%' OR di.icd_code LIKE 'G31%')
      THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN
      -- Chronic pulmonary disease
      (di.icd_version = 9 AND di.icd_code IN ('4168', '4169', '490', '491', '492', '493', '494', '495', '496', '500', '501', '502', '503', '504', '505', '5064', '5081', '5088')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'J40%' OR di.icd_code LIKE 'J41%' OR di.icd_code LIKE 'J42%' OR di.icd_code LIKE 'J43%' OR di.icd_code LIKE 'J44%' OR di.icd_code LIKE 'J45%' OR di.icd_code LIKE 'J46%' OR di.icd_code LIKE 'J47%' OR di.icd_code LIKE 'J60%' OR di.icd_code LIKE 'J61%' OR di.icd_code LIKE 'J62%' OR di.icd_code LIKE 'J63%' OR di.icd_code LIKE 'J64%' OR di.icd_code LIKE 'J65%' OR di.icd_code LIKE 'J66%' OR di.icd_code LIKE 'J67%' OR di.icd_code LIKE 'J684%' OR di.icd_code LIKE 'J701%' OR di.icd_code LIKE 'J703%')
      THEN 1 ELSE 0 END) AS pulm,
    MAX(CASE WHEN
      -- Rheumatic disease
      (di.icd_version = 9 AND di.icd_code IN ('4465', '7100', '7101', '7102', '7103', '7104', '7140', '7141', '7142', '71481', '725')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'M05%' OR di.icd_code LIKE 'M06%' OR di.icd_code LIKE 'M32%' OR di.icd_code LIKE 'M33%' OR di.icd_code LIKE 'M34%' OR di.icd_code LIKE 'M351%' OR di.icd_code LIKE 'M353%' OR di.icd_code LIKE 'M360%')
      THEN 1 ELSE 0 END) AS rheum,
    MAX(CASE WHEN
      -- Peptic ulcer disease
      (di.icd_version = 9 AND di.icd_code IN ('531', '532', '533', '534')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'K25%' OR di.icd_code LIKE 'K26%' OR di.icd_code LIKE 'K27%' OR di.icd_code LIKE 'K28%')
      THEN 1 ELSE 0 END) AS pud,
    MAX(CASE WHEN
      -- Mild liver disease
      (di.icd_version = 9 AND di.icd_code IN ('5712', '5714', '5715', '5716')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'B18%' OR di.icd_code LIKE 'K700%' OR di.icd_code LIKE 'K701%' OR di.icd_code LIKE 'K702%' OR di.icd_code LIKE 'K703%' OR di.icd_code LIKE 'K709%' OR di.icd_code LIKE 'K713%' OR di.icd_code LIKE 'K714%' OR di.icd_code LIKE 'K715%' OR di.icd_code LIKE 'K717%' OR di.icd_code LIKE 'K760%' OR di.icd_code LIKE 'K762%' OR di.icd_code LIKE 'K763%' OR di.icd_code LIKE 'K764%' OR di.icd_code LIKE 'K768%' OR di.icd_code LIKE 'K769%')
      THEN 1 ELSE 0 END) AS mild_liver,
    MAX(CASE WHEN
      -- Diabetes without chronic complication
      (di.icd_version = 9 AND di.icd_code IN ('2500', '2501', '2502', '2503')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'E100%' OR di.icd_code LIKE 'E101%' OR di.icd_code LIKE 'E106%' OR di.icd_code LIKE 'E108%' OR di.icd_code LIKE 'E109%' OR di.icd_code LIKE 'E110%' OR di.icd_code LIKE 'E111%' OR di.icd_code LIKE 'E116%' OR di.icd_code LIKE 'E118%' OR di.icd_code LIKE 'E119%' OR di.icd_code LIKE 'E120%' OR di.icd_code LIKE 'E121%' OR di.icd_code LIKE 'E126%' OR di.icd_code LIKE 'E128%' OR di.icd_code LIKE 'E129%' OR di.icd_code LIKE 'E130%' OR di.icd_code LIKE 'E131%' OR di.icd_code LIKE 'E136%' OR di.icd_code LIKE 'E138%' OR di.icd_code LIKE 'E139%' OR di.icd_code LIKE 'E140%' OR di.icd_code LIKE 'E141%' OR di.icd_code LIKE 'E146%' OR di.icd_code LIKE 'E148%' OR di.icd_code LIKE 'E149%')
      THEN 1 ELSE 0 END) AS dm_wo_cc,
    MAX(CASE WHEN
      -- Diabetes with chronic complication
      (di.icd_version = 9 AND di.icd_code IN ('2504', '2505', '2506', '2507', '2508', '2509')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'E102%' OR di.icd_code LIKE 'E103%' OR di.icd_code LIKE 'E104%' OR di.icd_code LIKE 'E105%' OR di.icd_code LIKE 'E107%' OR di.icd_code LIKE 'E112%' OR di.icd_code LIKE 'E113%' OR di.icd_code LIKE 'E114%' OR di.icd_code LIKE 'E115%' OR di.icd_code LIKE 'E117%' OR di.icd_code LIKE 'E122%' OR di.icd_code LIKE 'E123%' OR di.icd_code LIKE 'E124%' OR di.icd_code LIKE 'E125%' OR di.icd_code LIKE 'E127%' OR di.icd_code LIKE 'E132%' OR di.icd_code LIKE 'E133%' OR di.icd_code LIKE 'E134%' OR di.icd_code LIKE 'E135%' OR di.icd_code LIKE 'E137%' OR di.icd_code LIKE 'E142%' OR di.icd_code LIKE 'E143%' OR di.icd_code LIKE 'E144%' OR di.icd_code LIKE 'E145%' OR di.icd_code LIKE 'E147%')
      THEN 1 ELSE 0 END) AS dm_w_cc,
    MAX(CASE WHEN
      -- Hemiplegia or paraplegia
      (di.icd_version = 9 AND di.icd_code IN ('342', '343', '3440', '3441', '3442', '3443', '3444', '3445', '3446', '3449')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'G81%' OR di.icd_code LIKE 'G82%' OR di.icd_code LIKE 'G830%' OR di.icd_code LIKE 'G831%' OR di.icd_code LIKE 'G832%' OR di.icd_code LIKE 'G833%' OR di.icd_code LIKE 'G834%' OR di.icd_code LIKE 'G839%')
      THEN 1 ELSE 0 END) AS hemi_para,
    MAX(CASE WHEN
      -- Renal disease
      (di.icd_version = 9 AND di.icd_code IN ('582', '5830', '5831', '5832', '5833', '5834', '5836', '5837', '585', '586', '5880', 'V420', 'V451', 'V560', 'V561', 'V562')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'I12%' OR di.icd_code LIKE 'I13%' OR di.icd_code LIKE 'N03%' OR di.icd_code LIKE 'N05%' OR di.icd_code LIKE 'N18%' OR di.icd_code LIKE 'N19%' OR di.icd_code LIKE 'N25%' OR di.icd_code LIKE 'Z490%' OR di.icd_code LIKE 'Z491%' OR di.icd_code LIKE 'Z492%' OR di.icd_code LIKE 'Z940%' OR di.icd_code LIKE 'Z992%')
      THEN 1 ELSE 0 END) AS renal,
    MAX(CASE WHEN
      -- Any malignancy, including lymphoma and leukemia, except malignant neoplasm of skin
      (di.icd_version = 9 AND (
        (di.icd_code BETWEEN '140' AND '172') OR
        (di.icd_code BETWEEN '174' AND '195') OR
        (di.icd_code BETWEEN '200' AND '208')
      )) OR
      (di.icd_version = 10 AND (
        (di.icd_code LIKE 'C0%' OR di.icd_code LIKE 'C1%' OR di.icd_code LIKE 'C2%' OR di.icd_code LIKE 'C3%' OR di.icd_code LIKE 'C4%' OR di.icd_code LIKE 'C5%' OR di.icd_code LIKE 'C6%' OR di.icd_code LIKE 'C7%' OR di.icd_code LIKE 'C8%' OR di.icd_code LIKE 'C9%' OR di.icd_code LIKE 'C96%')
      ))
      THEN 1 ELSE 0 END) AS malignancy,
    MAX(CASE WHEN
      -- Moderate or severe liver disease
      (di.icd_version = 9 AND di.icd_code IN ('5722', '5723', '5724', '5728')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'K704%' OR di.icd_code LIKE 'K711%' OR di.icd_code LIKE 'K721%' OR di.icd_code LIKE 'K729%' OR di.icd_code LIKE 'K765%' OR di.icd_code LIKE 'K766%' OR di.icd_code LIKE 'K767%')
      THEN 1 ELSE 0 END) AS severe_liver,
    MAX(CASE WHEN
      -- Metastatic solid tumor
      (di.icd_version = 9 AND di.icd_code IN ('196', '197', '198', '199')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'C77%' OR di.icd_code LIKE 'C78%' OR di.icd_code LIKE 'C79%' OR di.icd_code LIKE 'C80%')
      THEN 1 ELSE 0 END) AS metastatic,
    MAX(CASE WHEN
      -- AIDS/HIV
      (di.icd_version = 9 AND di.icd_code IN ('042', '043', '044')) OR
      (di.icd_version = 10 AND di.icd_code LIKE 'B20%' OR di.icd_code LIKE 'B21%' OR di.icd_code LIKE 'B22%' OR di.icd_code LIKE 'B24%')
      THEN 1 ELSE 0 END) AS aids
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY
    di.hadm_id
),

charlson_score AS (
  -- Calculate Charlson index per admission
  SELECT
    cm.hadm_id,
    -- Charlson weights per category
    (
      1 * cm.mi +
      1 * cm.chf +
      1 * cm.pvd +
      1 * cm.cerebro +
      1 * cm.dementia +
      1 * cm.pulm +
      1 * cm.rheum +
      1 * cm.pud +
      1 * cm.mild_liver +
      1 * cm.dm_wo_cc +
      2 * cm.dm_w_cc +
      2 * cm.hemi_para +
      2 * cm.renal +
      2 * cm.malignancy +
      3 * cm.severe_liver +
      6 * cm.metastatic +
      6 * cm.aids
    ) AS charlson
  FROM
    charlson_map cm
),

admission_features AS (
  -- Combine all features per admission
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    fa.hospital_expire_flag,
    fa.anchor_age,
    df.has_sepsis,
    df.has_shock,
    cs.charlson,
    -- LOS in days
    SAFE_CAST(TIMESTAMP_DIFF(fa.dischtime, fa.admittime, DAY) AS INT64) AS los_days
  FROM
    female_admissions fa
    JOIN diagnosis_flags df
      ON fa.subject_id = df.subject_id AND fa.hadm_id = df.hadm_id
    LEFT JOIN charlson_score cs
      ON fa.hadm_id = cs.hadm_id
),

final_cohort AS (
  -- Filter to admissions with sepsis (with/without shock), valid Charlson, valid LOS
  SELECT
    *,
    CASE
      WHEN has_sepsis = 1 AND has_shock = 0 THEN 'Sepsis without shock'
      WHEN has_shock = 1 THEN 'Septic shock'
      ELSE NULL
    END AS sepsis_group,
    CASE
      WHEN los_days <= 7 THEN '≤7'
      WHEN los_days > 7 THEN '>7'
      ELSE NULL
    END AS los_group,
    CASE
      WHEN charlson <= 3 THEN '≤3'
      WHEN charlson BETWEEN 4 AND 5 THEN '4–5'
      WHEN charlson > 5 THEN '>5'
      ELSE NULL
    END AS charlson_group
  FROM
    admission_features
  WHERE
    (has_sepsis = 1 OR has_shock = 1)
    AND charlson IS NOT NULL
    AND los_days IS NOT NULL
)

-- Aggregate mortality by sepsis group, LOS group, Charlson group
, mortality_stats AS (
  SELECT
    sepsis_group,
    los_group,
    charlson_group,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS mortality_pct
  FROM
    final_cohort
  WHERE
    sepsis_group IS NOT NULL
    AND los_group IS NOT NULL
    AND charlson_group IS NOT NULL
  GROUP BY
    sepsis_group, los_group, charlson_group
)

-- Calculate absolute and relative differences between sepsis groups for each LOS/Charlson group
SELECT
  ms.sepsis_group,
  ms.los_group,
  ms.charlson_group,
  ms.n_admissions,
  ms.n_deaths,
  ROUND(ms.mortality_pct, 2) AS mortality_pct,
  -- Absolute and relative difference vs Sepsis without shock (for same LOS/Charlson group)
  ROUND(ms.mortality_pct - sws.mortality_pct, 2) AS absolute_diff,
  ROUND(SAFE_DIVIDE(ms.mortality_pct, sws.mortality_pct), 2) AS relative_diff
FROM
  mortality_stats ms
  LEFT JOIN mortality_stats sws
    ON sws.sepsis_group = 'Sepsis without shock'
    AND sws.los_group = ms.los_group
    AND sws.charlson_group = ms.charlson_group
ORDER BY
  los_group, charlson_group, sepsis_group;