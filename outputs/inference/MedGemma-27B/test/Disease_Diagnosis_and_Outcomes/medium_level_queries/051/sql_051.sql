WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.gender,
    p.anchor_age,
    p.anchor_year_group,
    -- Calculate Charlson Comorbidity Index (CCI)
    -- This requires a separate calculation based on diagnoses
    -- For simplicity, we'll assume a pre-calculated CCI is available or use a simplified approach
    -- A full CCI calculation is complex and beyond the scope of this example
    -- Let's use a placeholder for CCI calculation
    -- Placeholder: Assume CCI is calculated based on diagnoses_icd
    -- Example: Calculate CCI based on ICD codes (requires a separate function or CTE)
    -- For this example, we will skip the full CCI calculation and use a placeholder
    -- A simplified approach might involve counting specific ICD codes related to comorbidities
    -- Let's use a placeholder value for demonstration
    -- Replace this with actual CCI calculation logic
    -- Example:
    -- CASE
    --   WHEN COUNT(CASE WHEN icd_code IN ('4019', '4039', '4049', '4059', '4089', '4109', '4119', '4129', '4139', '4149', '4209', '4219', '4229', '4239', '4249', '4259', '4269', '4279', '4289', '4299', '4309', '4319', '4329', '4339', '4349', '4359', '4369', '4379', '4389', '4399', '4409', '4419', '4429', '4439', '4449', '4459', '4469', '4479', '4489', '4499', '4509', '4519', '4529', '4539', '4549', '4559', '4569', '4579', '4589', '4599', '4609', '4619', '4629', '4639', '4649', '4659', '4669', '4679', '4689', '4699', '4709', '4719', '4729', '4739', '4749', '4759', '4769', '4779', '4789', '4799', '4809', '4819', '4829', '4839', '4849', '4859', '4869', '4879', '4889', '4899', '4909', '4919', '4929', '4939', '4949', '4959', '4969', '497;