WITH
-- Define Charlson comorbidities mapping (Quan et al. for ICD-9 and ICD-10)
charlson_map AS (
  SELECT
    icd_code,
    icd_version,
    weight,
    category
  FROM UNNEST(ARRAY<STRUCT<icd_code STRING, icd_version INT64, weight INT64, category STRING>>[
    -- Myocardial infarction
    ('I21', 10, 1, 'mi'), ('I22', 10, 1, 'mi'), ('I25', 10, 1, 'mi'),
    ('410', 9, 1, 'mi'), ('412', 9, 1, 'mi'),
    -- Congestive heart failure
    ('I50', 10, 1, 'chf'),
    ('428', 9, 1, 'chf'),
    -- Peripheral vascular disease
    ('I73', 10, 1, 'pvd'), ('I71', 10, 1, 'pvd'), ('I790', 10, 1, 'pvd'), ('I739', 10, 1, 'pvd'),
    ('4439', 9, 1, 'pvd'), ('441', 9, 1, 'pvd'), ('7854', 9, 极, 'pvd'), ('V434', 9, 1, 'pvd'),
    -- Cerebrovascular disease
    ('G45', 10, 1, 'cvd'), ('G46', 10, 1, 'cvd'), ('I60', 10, 1, 'cvd'), ('I69', 10, 1, 'cvd'),
    ('430', 9, 1, 'cvd'), ('431', 9, 1, 'cvd'), ('433', 9, 1, 'cvd'), ('434', 9, 1, 'c极d'), ('435', 9, 1, 'cvd'),
    -- Dementia
    ('F00', 10, 1, 'dementia'), ('F01', 10, 1, 'dementia'), ('F02', 10, 1, 'dementia'), ('F03', 10, 1, 'dementia'),
    ('290', 9, 1, 'dementia'),
    -- Chronic pulmonary disease
    ('J44', 10, 1, 'cpd'), ('J43', 10, 1, 'cpd'), ('J42', 10, 1, 'cpd'), ('J41', 10, 1, 'cpd'),
    ('490', 9, 1, 'cpd'), ('491', 9, 1, 'cpd'), ('492', 9, 1, 'cpd'), ('493', 9, 1, 'cpd'), ('494', 9, 1, 'cpd'), ('495', 9, 1, 'cpd'),
    -- Rheumatologic disease
    ('M32', 10, 1, 'rheum'), ('M34', 10, 1, 'rheum'), ('M05', 10, 1, 'rheum'), ('M06', 10, 1, 'rheum'),
    ('7100', 9, 1, 'rheum'), ('7101', 9, 1, 'rheum'), ('7104', 9, 1, 'rheum'), ('7140', 9, 1, 'rheum'), ('7141', 9, 1, 'rheum'), ('7142', 9, 1, 'rheum'),
    -- Peptic ulcer disease
    ('K25', 10, 1, 'pud'), ('K26', 10, 1, 'pud'), ('K27', 10, 1, 'pud'), ('K28', 10, 1, 'pud'),
    ('531', 9, 1, 'pud'), ('532', 9, 1, 'pud'), ('533', 9, 1, 'pud'), ('534', 9, 1, 'pud'),
    -- Mild liver disease
    ('B18', 10, 1极, 'mld'), ('K70', 10, 1, 'mld'), ('K71', 10, 1, 'mld'), ('K73', 10, 1, 'mld'), ('K74', 10, 1, 'mld'),
    ('570', 9, 1, 'mld'), ('571', 9, 1, 'mld'),
    -- Diabetes without chronic complication
    ('E10', 10, 1, 'diab'), ('E11', 10, 1, 'diab'),
    ('2500', 9, 1, 'diab'), ('2501', 9, 1, 'diab'),
    -- Diabetes with chronic complication
    ('E10', 10, 2, 'diabwc'), ('E11', 10, 2, 'diabwc'),
    ('2502', 9, 2, 'diabwc'), ('2503', 9, 2, 'diabwc'),
    -- Hemiplegia or paraplegia
    ('G81', 10, 2, 'plegia'), ('G82', 10, 2, 'plegia'),
    ('3441', 9, 2, 'plegia'), ('342', 9, 2, 'plegia'),
    -- Renal disease
    ('N18', 10, 2, 'renal'), ('N19', 10, 2, 'renal'),
    ('583', 9, 2, 'renal'), ('584', 9, 2, 'renal'), ('585', 9, 2, 'renal'), ('586', 9, 2, 'renal'), ('588', 9, 2, 'renal'),
    -- Any malignancy
    ('C0%', 10, 2, 'malignancy'), ('C1%', 10, 2, 'malignancy'), ('C2%', 10, 2, 'malignancy'), ('C3%', 10, 2, 'malignancy'), ('C4%', 10, 2, 'malignancy'), ('C5%', 10, 2, 'malignancy'), ('C6%', 10, 2, 'malignancy'), ('C7%', 10, 2, 'malignancy'), ('C8%', 10, 2, 'malignancy'),
    ('140', 9, 2, 'malignancy'), ('141', 9, 2, 'malignancy'), ('142', 9, 2, 'malignancy'), ('143', 9, 2, 'malignancy'), ('144', 9, 2, 'malignancy'), ('145', 9, 2, 'malignancy'), ('146', 9, 2, 'malignancy'), ('147', 9, 2, 'malignancy'), ('148', 9, 2, 'malignancy'), ('149', 9, 2, 'malignancy'), ('150', 9, 2, 'malignancy'), ('151', 9, 2, 'malignancy'), ('152', 9, 2, 'malignancy'), ('153', 9, 2, 'malignancy'), ('154', 9, 2, 'malignancy'), ('155', 9, 2, 'malignancy'), ('156', 9, 2, 'malignancy'), ('157', 9, 2, 'malignancy'), ('158', 9, 2, 'malignancy'), ('159', 9, 2, 'malignancy'), ('160', 9, 2, 'malignancy'), ('161', 9, 2, 'malignancy'), ('162', 9, 2, 'malignancy'), ('163', 9, 2, 'malignancy'), ('164', 9, 2, 'malignancy'), ('165', 9, 2, 'malignancy'), ('166', 9, 2, 'malignancy'), ('167', 9, 2, 'malignancy'), ('168', 9, 2, 'malignancy'), ('169', 9, 2, 'malignancy'), ('170', 9, 2, 'malignancy'), ('171', 9, 2, 'malignancy'), ('172', 9, 2, 'malignancy'), ('174', 9, 2, 'malignancy'), ('175', 9, 2, 'malignancy'), ('176', 9, 2, 'malignancy'), ('179', 9, 2, 'malignancy'), ('180', 9, 2, 'malignancy'), ('181', 9, 2, 'malignancy'), ('182', 9, 2, 'malignancy'), ('183', 9, 2, 'malignancy'), ('184', 极, 2, 'malignancy'), ('185', 9, 2, 'malignancy'), ('186', 9, 2, 'malignancy'), ('187', 9, 2, 'malignancy'), ('188', 9, 2, 'malignancy'), ('189', 9, 2, 'malignancy'), ('190', 9, 2, 'malignancy'), ('191', 9, 2, 'malignancy'), ('192', 9, 2, 'malignancy'), ('193', 9, 2, 'malignancy'), ('194', 9, 2, 'malignancy'), ('195', 9, 2, 'malignancy'),
    -- Moderate or severe liver disease
    ('I85', 10, 3, 'msld'), ('I864', 10, 3, 'msld'), ('I982', 10, 3, 'msld'), ('K704', 10, 3, 'msld'), ('K711', 10, 3, 'msld'), ('K721', 10, 3, 'msld'), ('K729', 10, 3, 'msld'), ('K765', 10, 3, 'msld'), ('K767', 10, 3, 'msld'),
    ('4560', 9, 3, 'msld'), ('4561', 9, 3, 'msld'), ('4562', 9, 3, 'msld'), ('5722', 9, 3, 'msld'), ('5723', 9, 3, 'msld'), ('5724', 9, 3, 'msld'), ('5728', 9, 3, 'msld'),
    -- Metastatic solid tumor
    ('C80', 10, 6, 'metastatic'),
    ('196', 9, 6, 'metastatic'), ('197', 9, 6, 'metastatic'), ('198', 9, 6, 'metastatic'), ('199', 9, 6, '极etastatic'),
    -- AIDS/HIV
    ('B20', 10, 6, 'hiv'),
    ('042', 9, 6, 'hiv')
  ])
),

-- Compute Charlson index per admission
charlson AS (
  SELECT
    diag.subject_id,
    diag.hadm_id,
    SUM(map.weight) AS charlson_index
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN charlson_map map
    ON (diag.icd_code LIKE map.icd_code OR diag.icd_code = map.icd_code)
    AND diag.icd_version = map.icd_version
  GROUP BY diag.subject_id, diag.hadm_id
),

-- Identify sepsis and septic shock
sepsis_codes AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN (icd_version = 9 AND icd_code IN ('78552')) OR
                  (icd_version = 10 AND icd_code IN ('R6520', 'R6521')) THEN 1
             ELSE 0 END) AS septic_shock,
    MAX(CASE WHEN (icd_version = 9 AND icd_code IN ('99591', '99592')) OR
                  (icd_version = 10 AND icd_code IN ('A419', 'A021', 'A207', 'A227', 'A267', 'A327', 'A392', 'A393', 'A394', 'A400', 'A401', 'A402', 'A403', 'A408', 'A409', 'A410', 'A411', 'A412', 'A413', 'A414', 'A415', 'A418', 'A419', 'B007', 'B377')) THEN 1
             ELSE 0 END) AS sepsis
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY subject_id, hadm_id
),

-- Base cohort: female patients aged 57-67 with sepsis or septic shock
base_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND EXISTS (
      SELECT 1
      FROM sepsis_codes s
      WHERE s.subject_id = p.subject_id AND s.hadm_id = a.hadm_id
      AND (s.sepsis = 1 OR s.septic_shock = 1)
    )
),

-- Combine everything
combined AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.hospital_expire_flag,
    b.los_days,
    COALESCE(c.charlson_index, 0) AS charlson_index,
    CASE
      WHEN s.septic_shock = 1 THEN 'Septic shock'
      WHEN s.sepsis = 1 THEN 'Sepsis without shock'
      ELSE 'None'
    END AS sepsis_group
  FROM base_cohort b
  LEFT JOIN sepsis_codes s
    ON b.subject_id = s.subject_id AND b.hadm_id = s.hadm_id
  LEFT JOIN charlson c
    ON b.subject_id = c.subject_id AND b.hadm_id = c.hadm_id
),

-- Group into categories and aggregate
categorized AS (
  SELECT
    sepsis_group,
    CASE WHEN los_days <= 7 THEN '<=7' ELSE '>7' END AS los_group,
    CASE
      WHEN charlson_index <= 3 THEN '<=3'
      WHEN charlson_index BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_group,
    COUNT(*) AS total_in_group,
    SUM(hospital_expire_flag) AS deaths_in_group
  FROM combined
  GROUP BY sepsis_group, los_group, charlson_group
),

-- Compute mortality %
agg AS (
  SELECT
    sepsis_group,
    los_group,
    charlson_group,
    total_in_group AS n,
    deaths_in_group AS deaths,
    ROUND(100.0 * deaths_in_group / total_in_group, 2) AS mortality_pct
  FROM categorized
),

-- Pivot to compare sepsis without shock vs septic shock
comparison AS (
  SELECT
    los_group,
    charlson_group,
    MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN n END) AS n_noshock,
    MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN deaths END) AS deaths_noshock,
    MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN mortality_pct END) AS mortality_noshock,
    MAX(CASE WHEN sepsis_group = 'Septic shock' THEN n END) AS n_shock,
    MAX(CASE WHEN sepsis_group = 'Septic shock' THEN deaths END) AS deaths_shock,
    MAX(CASE WHEN sepsis_group = 'Septic shock' THEN mortality_pct END) AS mortality_shock,
    ROUND(
      MAX(CASE WHEN sepsis_group = 'Septic shock' THEN mortality_pct END) -
      MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN mortality_pct END),
      2
    ) AS absolute_difference,
    ROUND(
      100.0 * (
        MAX(CASE WHEN sepsis_group = 'Septic shock' THEN mortality_pct END) -
        MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN mortality_pct END)
      ) / NULLIF(MAX(CASE WHEN sepsis_group = 'Sepsis without shock' THEN mortality_pct END), 0),
      2
    ) AS relative_difference_percent
  FROM agg
  GROUP BY los_group, charlson_group
)

-- Final output
SELECT
  los_group,
  charlson_group,
  n_noshock,
  deaths_noshock,
  mortality_noshock,
  n_shock,
  deaths_shock,
  mortality_shock,
  absolute_difference,
  relative_difference_percent
FROM comparison
ORDER BY los_group, charlson_group;